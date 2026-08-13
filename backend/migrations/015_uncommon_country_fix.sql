-- 015_uncommon_country_fix.sql — fix #48 ("roaster country should trust the
-- caption over the vocab guess").
--
-- Radu: "Uncommon resolved to UK though its bag says 'Prajitorie: Uncommon
-- (Amsterdam, Olanda)' = Netherlands." Root cause is a roaster NAME
-- collision, not a bad web search: 014_roaster_countries.sql's live web
-- search for "Uncommon" found a real UK "Uncommon Coffee Roasters" and set
-- country_id accordingly, but 005_vocab_seed.sql had already merged that
-- name with a different, real Amsterdam roaster (also called "Uncommon")
-- into the same seeded `roasters` row. Verified directly against production
-- (`GET /api/coffees/:id`): the corpus has exactly one "Uncommon" coffee, and
-- its own caption is unambiguous evidence for the Amsterdam identity. With
-- no second "Uncommon" record to anchor a genuine UK identity, splitting the
-- roaster row into two would be guessing in the other direction — a plain
-- correction is the smaller, verifiable fix.
UPDATE roasters
SET country_id = (SELECT id FROM countries WHERE name = 'Netherlands')
WHERE name = 'Uncommon';

-- Same backfill 014 already does for a freshly-set country_id: worker.js
-- only copies roaster_country_id from roasters.country_id at adjudication
-- time, so the already-adjudicated coffee row is stuck at the old (wrong)
-- value until fixed directly.
UPDATE coffees co
SET roaster_country_id = r.country_id
FROM roasters r
WHERE co.roaster_id = r.id AND r.name = 'Uncommon';

-- Durable half of #48: `deterministic.js`'s new `extractRoasterCountryField`
-- can propose `roaster_country_id` straight from an explicit "Prajitorie: X
-- (City, Country)" caption line, but only if the country vocab actually has
-- an alias for however the caption spells it. "Olanda" (Romanian for
-- Netherlands) was missing — the exact gap that let this specific caption's
-- own correction go unnoticed at extraction time in the first place.
INSERT INTO country_aliases (country_id, alias, alias_norm)
SELECT c.id, 'Olanda', 'olanda' FROM countries c WHERE c.name = 'Netherlands'
ON CONFLICT (alias_norm) DO NOTHING;
