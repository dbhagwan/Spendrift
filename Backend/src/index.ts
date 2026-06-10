import express from "express";
import { Pool } from "pg";
import { classifyTransaction } from "./ai.js";
import { createLinkToken, exchangePublicToken, fetchBalances, syncTransactions } from "./plaid.js";

const app = express();
app.use(express.json({ limit: "10mb" }));

const db = new Pool({ connectionString: process.env.DATABASE_URL });

// TODO(auth): exchange Sign in with Apple identity tokens for sessions and
// verify the Bearer token on every route below. For scaffold purposes a
// single demo user is upserted on the fly.
async function requireUser(_req: express.Request): Promise<string> {
  const result = await db.query(
    `INSERT INTO users (apple_user_id) VALUES ('dev-user')
     ON CONFLICT (apple_user_id) DO UPDATE SET apple_user_id = EXCLUDED.apple_user_id
     RETURNING id`
  );
  return result.rows[0].id;
}

// MARK: Plaid link flow

app.post("/plaid/link-token", async (req, res) => {
  const userId = await requireUser(req);
  const linkToken = await createLinkToken(userId);
  res.json({ linkToken });
});

app.post("/plaid/exchange", async (req, res) => {
  const userId = await requireUser(req);
  const { publicToken } = req.body;
  const { accessToken, itemId } = await exchangePublicToken(publicToken);

  // Access token is stored server-side only; the device never sees it.
  await db.query(
    `INSERT INTO plaid_items (user_id, plaid_item_id, access_token, institution_name)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (plaid_item_id) DO UPDATE SET access_token = EXCLUDED.access_token, requires_relink = FALSE`,
    [userId, itemId, accessToken, req.body.institutionName ?? "Linked Institution"]
  );

  await enqueue("sync_transactions", { itemId });
  res.json({ itemID: itemId, institutionName: req.body.institutionName ?? "Linked Institution" });
});

// MARK: Plaid webhooks — drive sync without device polling

app.post("/webhooks/plaid", async (req, res) => {
  // TODO(production): verify webhook JWT per Plaid docs before trusting payload.
  const { webhook_type: type, webhook_code: code, item_id: itemId } = req.body;

  if (type === "TRANSACTIONS" && ["SYNC_UPDATES_AVAILABLE", "DEFAULT_UPDATE", "INITIAL_UPDATE"].includes(code)) {
    await enqueue("sync_transactions", { plaidItemId: itemId });
  }
  if (type === "ITEM" && code === "PENDING_EXPIRATION") {
    await db.query(`UPDATE plaid_items SET requires_relink = TRUE WHERE plaid_item_id = $1`, [itemId]);
  }
  if (type === "ITEM" && code === "ERROR") {
    await db.query(`UPDATE plaid_items SET requires_relink = TRUE WHERE plaid_item_id = $1`, [itemId]);
  }
  res.sendStatus(200);
});

// MARK: Sync payload for the app

app.get("/sync", async (req, res) => {
  const userId = await requireUser(req);
  const accounts = await db.query(
    `SELECT a.plaid_account_id AS provider_account_id, i.institution_name, a.name, a.kind,
            a.subtype, a.mask, a.current_balance, a.available_balance, a.credit_limit, a.currency_code
     FROM accounts a JOIN plaid_items i ON i.id = a.item_id WHERE i.user_id = $1`,
    [userId]
  );
  const transactions = await db.query(
    `SELECT t.plaid_transaction_id AS provider_transaction_id, t.account_id, a.plaid_account_id AS provider_account_id,
            t.amount, t.date, t.merchant_name, t.raw_description, t.pending, t.provider_category,
            t.location_city, t.location_region
     FROM transactions t
     JOIN accounts a ON a.id = t.account_id
     JOIN plaid_items i ON i.id = a.item_id
     WHERE i.user_id = $1
     ORDER BY t.date DESC LIMIT 5000`,
    [userId]
  );
  res.json({ accounts: accounts.rows, transactions: transactions.rows });
});

// MARK: AI enrichment endpoint (called by app for low-confidence fallbacks)

app.post("/ai/classify", async (req, res) => {
  const { merchant, rawDescription, amount } = req.body;
  const result = await classifyTransaction({ merchant, rawDescription, amount });
  res.json(result);
});

// TODO(receipts): POST /receipts — accept image upload to object storage,
// run server-side extraction via ai.extractReceipt, persist to receipts table.

// MARK: Minimal inline job runner.
// TODO(production): replace with a real worker (pg-boss / BullMQ) and remove
// the inline processing below.

async function enqueue(kind: string, payload: object) {
  await db.query(`INSERT INTO jobs (kind, payload) VALUES ($1, $2)`, [kind, payload]);
  void processJobs();
}

let processing = false;
async function processJobs() {
  if (processing) return;
  processing = true;
  try {
    for (;;) {
      const job = await db.query(
        `UPDATE jobs SET status = 'running', started_at = now()
         WHERE id = (SELECT id FROM jobs WHERE status = 'queued' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
         RETURNING id, kind, payload`
      );
      if (job.rowCount === 0) break;
      const { id, kind, payload } = job.rows[0];
      try {
        if (kind === "sync_transactions") await runTransactionSync(payload);
        await db.query(`UPDATE jobs SET status = 'done', finished_at = now() WHERE id = $1`, [id]);
      } catch (error) {
        console.error(`job ${id} (${kind}) failed`, error);
        await db.query(`UPDATE jobs SET status = 'failed', finished_at = now() WHERE id = $1`, [id]);
      }
    }
  } finally {
    processing = false;
  }
}

async function runTransactionSync(payload: { itemId?: string; plaidItemId?: string }) {
  const item = await db.query(
    payload.itemId
      ? `SELECT id, access_token, transactions_cursor FROM plaid_items WHERE id = $1`
      : `SELECT id, access_token, transactions_cursor FROM plaid_items WHERE plaid_item_id = $1`,
    [payload.itemId ?? payload.plaidItemId]
  );
  if (item.rowCount === 0) return;
  const { id: itemDbId, access_token: accessToken, transactions_cursor: cursor } = item.rows[0];

  // Balances + accounts upsert.
  const accounts = await fetchBalances(accessToken);
  for (const account of accounts) {
    await db.query(
      `INSERT INTO accounts (item_id, plaid_account_id, name, kind, subtype, mask, current_balance, available_balance, credit_limit, currency_code)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (plaid_account_id) DO UPDATE SET
         current_balance = EXCLUDED.current_balance,
         available_balance = EXCLUDED.available_balance,
         credit_limit = EXCLUDED.credit_limit,
         updated_at = now()`,
      [
        itemDbId,
        account.account_id,
        account.name,
        mapAccountKind(account.type, account.subtype ?? ""),
        account.subtype,
        account.mask,
        account.balances.current,
        account.balances.available,
        account.balances.limit,
        account.balances.iso_currency_code ?? "USD",
      ]
    );
  }

  // Incremental transactions.
  const { added, modified, removed, cursor: nextCursor } = await syncTransactions(accessToken, cursor ?? undefined);
  for (const txn of [...added, ...modified]) {
    await db.query(
      `INSERT INTO transactions (account_id, plaid_transaction_id, amount, date, merchant_name, raw_description, pending, provider_category, location_city, location_region)
       SELECT a.id, $2, $3, $4, $5, $6, $7, $8, $9, $10 FROM accounts a WHERE a.plaid_account_id = $1
       ON CONFLICT (plaid_transaction_id) DO UPDATE SET
         amount = EXCLUDED.amount, pending = EXCLUDED.pending, date = EXCLUDED.date`,
      [
        txn.account_id,
        txn.transaction_id,
        txn.amount,
        txn.date,
        txn.merchant_name,
        txn.name,
        txn.pending,
        txn.personal_finance_category?.primary,
        txn.location?.city,
        txn.location?.region,
      ]
    );
  }
  for (const removal of removed) {
    await db.query(`DELETE FROM transactions WHERE plaid_transaction_id = $1`, [removal.transaction_id]);
  }

  await db.query(
    `UPDATE plaid_items SET transactions_cursor = $1, last_synced_at = now() WHERE id = $2`,
    [nextCursor, itemDbId]
  );
  // TODO(push): signal the device (APNs silent push) that fresh data is ready.
}

function mapAccountKind(type: string, subtype: string): string {
  if (type === "depository") return subtype === "savings" ? "savings" : "checking";
  if (type === "credit") return "creditCard";
  if (type === "loan") return "loan";
  if (type === "investment") return "investment";
  return "other";
}

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => {
  console.log(`Spendrift backend listening on :${port}`);
});
