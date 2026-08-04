-- 011_resolutions.sql — the adjudication substrate (PLAN.md §2):
-- `field_candidates` is the flattened per-field, per-agent view an extraction
-- run adds to; `field_resolutions` is the decided value per field with the
-- human-sticky `locked` flag ("the single most important invariant in the
-- pipeline" — PLAN.md §1: without it, the monthly incremental run silently
-- undoes a review decision); `review_items` is the queue for anything
-- adjudication can't decide alone. `extraction_jobs` gives
-- `POST /api/admin/jobs/:id/pause` a row to record a spend cap and progress
-- against, so Radu can stop a runaway run without a redeploy.
--
-- The two lease columns on `photos` are the extraction worker's claim
-- mechanism: `src/lib/worker.js` claims a batch with `FOR UPDATE SKIP LOCKED`
-- inside a short transaction, stamps a lease here, then does the slow network
-- work (LLM calls) *outside* that transaction. A 10-minute-old lease is
-- reaped at the start of the next claim, which is what makes a SIGTERM'd
-- worker (an unrelated backend deploy, CLAUDE.md §12) recoverable rather than
-- stuck forever.

ALTER TABLE photos
  ADD COLUMN IF NOT EXISTS extraction_leased_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS extraction_leased_by TEXT;

CREATE TABLE IF NOT EXISTS field_candidates (
  id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  photo_id      BIGINT      NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  extraction_id BIGINT      NOT NULL REFERENCES extractions (id) ON DELETE CASCADE,
  agent         TEXT        NOT NULL,
  field         TEXT        NOT NULL,
  value         JSONB,
  confidence    NUMERIC(4, 3),
  evidence      TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Idempotency for the worker's own re-runs: an extraction row can be reused
  -- across runs (see 010's comment), but the same (photo, extraction, field)
  -- must only ever contribute one candidate row.
  UNIQUE (photo_id, extraction_id, field)
);

CREATE INDEX IF NOT EXISTS idx_field_candidates_photo_field ON field_candidates (photo_id, field);

CREATE TABLE IF NOT EXISTS field_resolutions (
  id           BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  photo_id     BIGINT      NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  field        TEXT        NOT NULL,
  value        JSONB,
  confidence   NUMERIC(4, 3),
  agreement    NUMERIC(4, 3),
  voters       TEXT[]      NOT NULL DEFAULT '{}',
  decided_by   TEXT        NOT NULL DEFAULT 'adjudication' CHECK (decided_by IN ('adjudication', 'human')),
  locked       BOOLEAN     NOT NULL DEFAULT false,
  decided_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (photo_id, field)
);

CREATE TABLE IF NOT EXISTS review_items (
  id             BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  photo_id       BIGINT      NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  field          TEXT        NOT NULL,
  reason         TEXT        NOT NULL,
  candidates     JSONB       NOT NULL,
  status         TEXT        NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'dismissed')),
  resolved_value JSONB,
  resolved_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partial-unique on open (PLAN.md §1): a field can only have one *open* item
-- at a time, but resolved/dismissed history is kept rather than overwritten.
CREATE UNIQUE INDEX IF NOT EXISTS idx_review_items_open_unique
  ON review_items (photo_id, field) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_review_items_status ON review_items (status);

CREATE TABLE IF NOT EXISTS extraction_jobs (
  id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  status        TEXT        NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'paused', 'done')),
  voter_set     TEXT        NOT NULL DEFAULT 'full',
  spend_cap_usd NUMERIC(10, 2),
  spent_usd     NUMERIC(10, 4) NOT NULL DEFAULT 0,
  photos_done   INT         NOT NULL DEFAULT 0,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  paused_at     TIMESTAMPTZ,
  finished_at   TIMESTAMPTZ,
  last_error    TEXT
);
