-- 003_extensions.sql — trigram + unaccent, best-effort.
--
-- Fuzzy vocabulary matching (src/lib/fuzzy.js) does its own normalization and
-- similarity scoring in JS, so nothing in the app hard-depends on these
-- extensions being installed — pg_trgm just lets a trigram GIN index speed up
-- autocomplete later. Some managed Postgres hosts (including Railway shared
-- plans) don't grant CREATE EXTENSION to the app role, so swallow that one
-- error rather than failing the whole migration run.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'pg_trgm: insufficient privilege, skipping (fuzzy matching still works in JS)';
END $$;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS unaccent;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'unaccent: insufficient privilege, skipping (diacritics are folded in JS)';
END $$;
