import {
  Configuration,
  CountryCode,
  PlaidApi,
  PlaidEnvironments,
  Products,
} from "plaid";

const configuration = new Configuration({
  basePath: PlaidEnvironments[process.env.PLAID_ENV ?? "sandbox"],
  baseOptions: {
    headers: {
      "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID ?? "",
      "PLAID-SECRET": process.env.PLAID_SECRET ?? "",
    },
  },
});

export const plaid = new PlaidApi(configuration);

/** Create a link_token for the iOS app to open Plaid Link. */
export async function createLinkToken(userId: string): Promise<string> {
  const response = await plaid.linkTokenCreate({
    user: { client_user_id: userId },
    client_name: "Spendrift",
    products: [Products.Transactions],
    // Liabilities/investments can be added per-institution later:
    // optional_products: [Products.Liabilities, Products.Investments],
    country_codes: [CountryCode.Us],
    language: "en",
    webhook: process.env.PLAID_WEBHOOK_URL || undefined,
  });
  return response.data.link_token;
}

/** Exchange a public_token from Link for an access_token (stored server-side only). */
export async function exchangePublicToken(publicToken: string) {
  const exchange = await plaid.itemPublicTokenExchange({ public_token: publicToken });
  return {
    accessToken: exchange.data.access_token,
    itemId: exchange.data.item_id,
  };
}

/**
 * Incremental transaction sync via /transactions/sync.
 * Returns added/modified/removed plus the new cursor to persist.
 */
export async function syncTransactions(accessToken: string, cursor?: string) {
  const added = [];
  const modified = [];
  const removed = [];
  let nextCursor = cursor;
  let hasMore = true;

  while (hasMore) {
    const response = await plaid.transactionsSync({
      access_token: accessToken,
      cursor: nextCursor,
      count: 500,
    });
    added.push(...response.data.added);
    modified.push(...response.data.modified);
    removed.push(...response.data.removed);
    nextCursor = response.data.next_cursor;
    hasMore = response.data.has_more;
  }

  return { added, modified, removed, cursor: nextCursor };
}

export async function fetchBalances(accessToken: string) {
  const response = await plaid.accountsBalanceGet({ access_token: accessToken });
  return response.data.accounts;
}
