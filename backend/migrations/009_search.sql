-- 009_search.sql — full-text search over coffees. `'simple'`, not `'english'`:
-- the corpus mixes Romanian captions with Czech/Dutch/Danish roaster copy, and
-- English stemming would mangle all of it (PLAN.md §1). Diacritics are folded
-- in JS before either blob column is written, so to_tsvector never needs
-- unaccent() (which is STABLE and couldn't back a generated column anyway).
--
-- Two plain blob columns hold the pre-folded text; the tsvector itself is
-- generated from them so it can never drift out of sync with a write.
-- `setweight` + `||` are both IMMUTABLE, so labels (A) outrank prose (D) in a
-- legal generated column.

ALTER TABLE coffees
  ADD COLUMN IF NOT EXISTS search_labels_blob TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS search_prose_blob  TEXT NOT NULL DEFAULT '';

ALTER TABLE coffees
  ADD COLUMN IF NOT EXISTS search_tsv tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('simple'::regconfig, search_labels_blob), 'A') ||
    setweight(to_tsvector('simple'::regconfig, search_prose_blob), 'D')
  ) STORED;

-- The two indexes PLAN.md §1 says earn their keep at ~900 rows: ranked FTS,
-- and containment for the origin-country facet (a blend must count in both
-- member countries, which `@>`/`&&` over the array makes a one-liner).
CREATE INDEX IF NOT EXISTS idx_coffees_search_tsv         ON coffees USING gin (search_tsv);
CREATE INDEX IF NOT EXISTS idx_coffees_origin_country_ids ON coffees USING gin (origin_country_ids);
