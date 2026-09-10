-- 034_add_congo_origin_country.sql — backlog #165 (Radu, 2026-09-04:
-- "Cafea Gardelli Sopacdi (Congo) MAI 2018 aeropress" extracted neither the
-- origin country nor the farm).
--
-- Root cause (a) of that report: Congo is entirely absent from the country
-- vocab — `grep -ri congo backend/` returned nothing — so
-- `extractOriginCountriesField` (deterministic.js:76) can never match it. The
-- country vocab is closed, exactly like #18's Cameroon-as-origin.
--
-- SOPACDI is a well-known cooperative in South Kivu, so the country meant here
-- is the **Democratic Republic of the Congo**.
--
-- DECISION on the row's open question ("is plain 'Republic of the Congo' also
-- wanted, or should it stay ambiguous?"): bare "Congo" maps to the DRC, and
-- Congo-Brazzaville is NOT seeded. Two reasons. First, it is the right answer
-- for a coffee context — the DRC is a real specialty origin (Kivu), while the
-- Republic of the Congo exports essentially no specialty coffee, so a bag
-- saying "Congo" means the DRC in every case Radu will meet. Second, the
-- ambiguity the question worries about cannot actually exist here:
-- `country_aliases.alias_norm` is UNIQUE, so the string 'congo' can only ever
-- belong to one country row. Reversible if that ever changes — repoint the
-- alias, don't add a competing one.

INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Democratic Republic of the Congo', 'CD', true, false, 'country')
ON CONFLICT (name) DO NOTHING;

-- `alias_norm` must equal `normalizeVocabString(alias)` = trim, collapse inner
-- whitespace, lowercase. Diacritics are deliberately NOT folded here:
-- `findAliasMentions` folds both sides before comparing, so a caption written
-- without them still matches.
INSERT INTO country_aliases (country_id, alias, alias_norm)
SELECT c.id, v.alias, v.alias_norm FROM (VALUES
  ('Democratic Republic of the Congo', 'Democratic Republic of the Congo', 'democratic republic of the congo'),
  ('Democratic Republic of the Congo', 'Congo', 'congo'),
  ('Democratic Republic of the Congo', 'DR Congo', 'dr congo'),
  ('Democratic Republic of the Congo', 'DRC', 'drc'),
  -- Radu's captions are Romanian/French-influenced ("R.D. Congo", "RDC"),
  -- the same reason 020 had to seed Romanian roaster-country aliases.
  ('Democratic Republic of the Congo', 'RDC', 'rdc'),
  ('Democratic Republic of the Congo', 'R.D. Congo', 'r.d. congo'),
  ('Democratic Republic of the Congo', 'Congo-Kinshasa', 'congo-kinshasa')
) AS v(country_name, alias, alias_norm)
JOIN countries c ON c.name = v.country_name
ON CONFLICT (alias_norm) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Same bug, four more countries: a country with NO alias row is unmatchable.
--
-- `findAliasMentions` scans `country_aliases` ONLY — a country's own name is
-- not implicitly an alias. 005_vocab_seed.sql knew this and seeded a
-- self-alias for every country it inserted ('Ethiopia' -> 'ethiopia'), but
-- every later migration that added a country forgot to:
--
--   018 Cameroon · 021 Hong Kong · 023 Japan · 024 Greece
--
-- All four have been silently unmatchable since they were added — Cameroon as
-- an origin, the other three as roaster countries — which is the same failure
-- #165 reported for Congo, just never noticed because nobody tested a bag from
-- one of them. Writing Congo's aliases by hand and leaving these four broken
-- would have made this the fifth instance.
--
-- Driven off the schema rather than a hardcoded list of four, so it also
-- repairs any country a future migration inserts without an alias. Idempotent:
-- a no-op once every country's own name is an alias.
INSERT INTO country_aliases (country_id, alias, alias_norm)
SELECT c.id, c.name, lower(trim(regexp_replace(c.name, '\s+', ' ', 'g')))
FROM countries c
WHERE NOT EXISTS (
  SELECT 1 FROM country_aliases a
  WHERE a.alias_norm = lower(trim(regexp_replace(c.name, '\s+', ' ', 'g')))
)
ON CONFLICT (alias_norm) DO NOTHING;
