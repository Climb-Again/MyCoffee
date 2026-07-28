-- 001_init.sql — base tables for the MyCoffee backend skeleton.
-- Forward-only. Each migration runs in its own transaction (see src/migrate.js).

-- Raw events posted by the iOS app via POST /api/ingest.
CREATE TABLE IF NOT EXISTS ingest_events (
  id           BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  type         TEXT        NOT NULL,
  payload      JSONB       NOT NULL DEFAULT '{}'::jsonb,
  captured_at  TIMESTAMPTZ NOT NULL,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ingest_events_type_captured
  ON ingest_events (type, captured_at DESC);
