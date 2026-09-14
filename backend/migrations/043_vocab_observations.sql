-- 043 (#198): a log of what the browser extension proposed to the vocab.
--
-- Radu, 2026-09-12: "add new items to database (not to my coffees!! just save
-- to database so we have them later): roaster overview, origin/roaster country
-- (if new country), roaster logo".
--
-- The point of the table is inspectability, not enforcement: the writes
-- themselves land on `roasters` / `roaster_aliases` / `country_aliases` through
-- the same get-or-create path a human accept uses (#36). This records what came
-- in, from which page, and what the endpoint did with it — so "where did that
-- roaster come from?" has an answer, and a bad scrape can be traced back to the
-- page that produced it rather than being indistinguishable from a human edit.
--
-- `applied` is false when the endpoint deliberately declined: the row already
-- had a value (never overwritten), or a country name did not resolve against
-- the closed seeded list.
CREATE TABLE IF NOT EXISTS vocab_observations (
  id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind            TEXT        NOT NULL CHECK (kind IN (
                                'roaster', 'roaster_blurb', 'roaster_logo',
                                'roaster_country', 'country_alias', 'origin_country')),
  target_id       INTEGER,
  source_url      TEXT,
  extracted_value TEXT,
  applied         BOOLEAN     NOT NULL DEFAULT false,
  observed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The only read pattern is "what landed recently", for the /api/status counter.
CREATE INDEX IF NOT EXISTS vocab_observations_observed_idx ON vocab_observations (observed_at DESC);
