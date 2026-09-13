-- #194 — backend-backed shortlist so the extension's Top-coffees list (#187)
-- syncs across browsers (Chrome, Brave, Firefox) and can be read from iOS
-- later (#195). Today the list lives only in each browser's
-- chrome.storage.local, so Chrome-at-home and Brave-at-work share nothing.
--
-- Keyed by token_hash (sha256 of the bearer), never the plaintext token, so
-- the DB never carries the credential. One shared INGEST_TOKEN today means one
-- shared shortlist; the key is here so a per-device / per-user identity later
-- needs no redesign, only a second column feeding the same PK.
--
-- Pruning is the server's job (#187's reasoning): a client that has been closed
-- for 10 days must not un-prune a row on its next sync, so retention is
-- enforced on write against server time, not by any client timer.
--
-- payload is the row exactly as history.js renders it (entryFromScore's shape);
-- the server stores and returns it opaquely and only reads `url` (to derive
-- url_key) and `savedAt`.
CREATE TABLE IF NOT EXISTS history (
  token_hash TEXT NOT NULL,
  url_key    TEXT NOT NULL,
  saved_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload    JSONB NOT NULL,
  PRIMARY KEY (token_hash, url_key)
);

-- The read path is always "this token's rows, newest first"; the write path
-- prunes by (token_hash, saved_at). Both are covered by this index.
CREATE INDEX IF NOT EXISTS history_token_saved_idx ON history (token_hash, saved_at DESC);
