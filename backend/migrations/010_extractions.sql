-- 010_extractions.sql — raw per-(agent, exact input) responses from the
-- 5-voter extraction pipeline (PLAN.md §2). Every LLM/rules response is
-- stored forever and adjudication (011) reads only these stored rows, so
-- re-adjudicating all ~900 records with new thresholds costs $0 (PLAN.md §2,
-- "Every raw response is stored forever").
--
-- input_sha = sha256(agent|provider|model|promptVersion|imageSha|textSha|
-- vocabVersion) — content-derived, not photo_id-derived, so the same exact
-- question (byte-identical image+caption) is never paid for twice even across
-- two photo rows. That's why the unique constraint is on input_sha alone; a
-- single extraction row can back field_candidates for more than one photo.

CREATE TABLE IF NOT EXISTS extractions (
  id             BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  agent          TEXT        NOT NULL CHECK (agent IN ('extract_a', 'extract_b', 'rules', 'critic', 'reconciler')),
  provider       TEXT        NOT NULL,              -- 'vertex' | 'rules'
  model          TEXT,                              -- e.g. 'gemini-2.5-pro'; NULL for rules
  prompt_version TEXT        NOT NULL,
  input_sha      CHAR(64)    NOT NULL UNIQUE,
  response       JSONB       NOT NULL,
  usage          JSONB,
  cost_usd       NUMERIC(10, 4) NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_extractions_agent ON extractions (agent);
