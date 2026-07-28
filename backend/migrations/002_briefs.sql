-- 002_briefs.sql — generated briefs served by GET /api/brief.

CREATE TABLE IF NOT EXISTS briefs (
  id           BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title        TEXT        NOT NULL,
  body         TEXT        NOT NULL,
  meta         JSONB       NOT NULL DEFAULT '{}'::jsonb,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_briefs_generated_at
  ON briefs (generated_at DESC);
