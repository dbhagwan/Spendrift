-- Spendrift backend schema (PostgreSQL).
-- Plaid access tokens live ONLY here, never on devices.

CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_user_id   TEXT UNIQUE NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS plaid_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plaid_item_id   TEXT UNIQUE NOT NULL,
    -- TODO(production): encrypt at rest with a KMS-managed key (pgcrypto or app-level envelope encryption).
    access_token    TEXT NOT NULL,
    institution_name TEXT NOT NULL,
    transactions_cursor TEXT,            -- Plaid /transactions/sync cursor
    requires_relink BOOLEAN NOT NULL DEFAULT FALSE,
    last_synced_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id             UUID NOT NULL REFERENCES plaid_items(id) ON DELETE CASCADE,
    plaid_account_id    TEXT UNIQUE NOT NULL,
    name                TEXT NOT NULL,
    kind                TEXT NOT NULL,    -- checking | savings | creditCard | loan | investment | other
    subtype             TEXT,
    mask                TEXT,
    current_balance     NUMERIC(14, 2),
    available_balance   NUMERIC(14, 2),
    credit_limit        NUMERIC(14, 2),
    currency_code       TEXT NOT NULL DEFAULT 'USD',
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    plaid_transaction_id    TEXT UNIQUE NOT NULL,
    amount                  NUMERIC(14, 2) NOT NULL,  -- positive = outflow (Plaid convention)
    date                    DATE NOT NULL,
    merchant_name           TEXT,
    raw_description         TEXT NOT NULL,
    pending                 BOOLEAN NOT NULL DEFAULT FALSE,
    provider_category       TEXT,
    -- AI enrichment (filled by the enrichment job)
    category                TEXT,
    subcategory             TEXT,
    category_confidence     REAL,
    is_essential            BOOLEAN,
    location_city           TEXT,
    location_region         TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_transactions_account_date ON transactions(account_id, date DESC);

CREATE TABLE IF NOT EXISTS receipts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Object-storage key for the receipt image (S3/GCS). TODO(production): wire object storage.
    image_key           TEXT NOT NULL,
    ocr_text            TEXT,
    extraction          JSONB,            -- structured ReceiptExtraction
    matched_transaction UUID REFERENCES transactions(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Append-only job queue for sync/enrichment work.
-- TODO(production): replace with a real queue (pg-boss, BullMQ, SQS).
CREATE TABLE IF NOT EXISTS jobs (
    id          BIGSERIAL PRIMARY KEY,
    kind        TEXT NOT NULL,            -- sync_transactions | enrich_transactions | recompute_insights
    payload     JSONB NOT NULL DEFAULT '{}',
    status      TEXT NOT NULL DEFAULT 'queued',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at  TIMESTAMPTZ,
    finished_at TIMESTAMPTZ
);
