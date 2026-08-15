-- 020_add_romanian_roaster_country_aliases.sql — #48(b)
--
-- Radu's captions are written in Romanian ("Prăjitorie: Uncommon (Amsterdam,
-- Olanda)"), but 005_vocab_seed.sql only ever seeded English country names/
-- aliases for roaster countries. The new caption-city override
-- (`deterministic.js`'s `extractRoasterCountryOverride`) can only recognise a
-- country stated in a caption if that spelling is a known alias — without
-- these, "Olanda" never resolves and the override this row exists for never
-- fires for the one caption pattern that actually motivated it. Skips a
-- handful of countries whose Romanian name is identical to the English one
-- already seeded (Canada, Austria, Slovenia, Romania) — nothing to add there.
--
-- Diacritics are kept as typed (e.g. 'Franța', 'Elveția') — alias_norm exact
-- lookups (`resolveVocab`) don't fold them, but the new override goes through
-- `findAliasMentions`, which folds both sides before comparing, so a
-- diacritic-free caption spelling ("Franta") still matches.

INSERT INTO country_aliases (country_id, alias, alias_norm)
SELECT c.id, v.alias, v.alias_norm FROM (VALUES
  ('Belgium', 'Belgia', 'belgia'),
  ('Czech Republic', 'Cehia', 'cehia'),
  ('Denmark', 'Danemarca', 'danemarca'),
  ('France', 'Franța', 'franța'),
  ('Germany', 'Germania', 'germania'),
  ('Ireland', 'Irlanda', 'irlanda'),
  ('Latvia', 'Letonia', 'letonia'),
  ('Netherlands', 'Olanda', 'olanda'),
  ('Norway', 'Norvegia', 'norvegia'),
  ('Poland', 'Polonia', 'polonia'),
  ('Slovakia', 'Slovacia', 'slovacia'),
  ('Spain', 'Spania', 'spania'),
  ('United States', 'SUA', 'sua'),
  ('United States', 'Statele Unite', 'statele unite'),
  ('United Kingdom', 'Marea Britanie', 'marea britanie'),
  ('United Kingdom', 'Anglia', 'anglia'),
  ('Italy', 'Italia', 'italia'),
  ('Sweden', 'Suedia', 'suedia'),
  ('Finland', 'Finlanda', 'finlanda'),
  ('South Korea', 'Coreea de Sud', 'coreea de sud'),
  ('Switzerland', 'Elveția', 'elveția')
) AS v(country_name, alias, alias_norm)
JOIN countries c ON c.name = v.country_name
ON CONFLICT (alias_norm) DO NOTHING;
