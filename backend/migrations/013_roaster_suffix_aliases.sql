-- 013_roaster_suffix_aliases.sql — accept the "<name> Roasters" spelling.
--
-- The 5-photo sample (#26) failed to resolve a roaster whose caption read
-- "Radical Coffee Roasters" while the vocabulary held "Radical Coffee": the
-- resolver does an EXACT alias_norm lookup on the whole value, so the longer
-- shop-copy form matched nothing and the field went to review. That is a class
-- of miss, not one row — Romanian shop copy freely appends "Roasters" /
-- "Coffee Roasters" to a roaster whose brand name omits it.
--
-- So rather than special-casing Radical, generate the suffixed spellings for
-- every roaster that doesn't already carry them. alias_norm mirrors
-- normalize.js's normalizeVocabString(): trim, collapse whitespace, lowercase
-- (no diacritic folding there, so plain lower() is faithful here).
--
-- ON CONFLICT DO NOTHING throughout: alias_norm is UNIQUE, so if one of these
-- spellings is already seeded (or would collide with another roaster's real
-- name) the existing row wins and this is a no-op. Forward-only and re-runnable.

-- "<name> Roasters" for roasters with no "roaster" anywhere in the name
-- (e.g. "Radical Coffee" -> "Radical Coffee Roasters").
INSERT INTO roaster_aliases (roaster_id, alias, alias_norm)
SELECT r.id, r.name || ' Roasters', lower(regexp_replace(btrim(r.name || ' Roasters'), '\s+', ' ', 'g'))
FROM roasters r
WHERE r.name NOT ILIKE '%roaster%'
ON CONFLICT (alias_norm) DO NOTHING;

-- "<name> Coffee Roasters" for roasters whose name mentions neither
-- (e.g. "Kolibri" -> "Kolibri Coffee Roasters").
INSERT INTO roaster_aliases (roaster_id, alias, alias_norm)
SELECT r.id, r.name || ' Coffee Roasters', lower(regexp_replace(btrim(r.name || ' Coffee Roasters'), '\s+', ' ', 'g'))
FROM roasters r
WHERE r.name NOT ILIKE '%roaster%' AND r.name NOT ILIKE '%coffee%'
ON CONFLICT (alias_norm) DO NOTHING;

-- The reverse direction: a caption may drop the suffix the canonical name
-- carries ("DAK Coffee Roasters" -> "DAK Coffee"). Only strips a trailing
-- " Roasters", never the brand's own words.
INSERT INTO roaster_aliases (roaster_id, alias, alias_norm)
SELECT r.id, regexp_replace(r.name, '\s+Roasters$', '', 'i'), lower(regexp_replace(regexp_replace(r.name, '\s+Roasters$', '', 'i'), '\s+', ' ', 'g'))
FROM roasters r
WHERE r.name ~* '\s+Roasters$'
ON CONFLICT (alias_norm) DO NOTHING;
