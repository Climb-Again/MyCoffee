-- 016_fix_manufaktura_roaster.sql — Radu: correct roaster spelling.
-- The extractor created the roaster as "Manufactura"; the real name is
-- "Manufaktura". Rename the vocab row in place: every coffee references the
-- roaster by id, and the snapshot ships the full roaster list on every sync,
-- so the corrected name shows everywhere on the app's next sync without
-- touching any coffee row. Keep the old spelling as an alias so a future
-- extraction that reads "Manufactura" resolves to this same roaster instead
-- of recreating the misspelled vocab entry.

UPDATE roasters SET name = 'Manufaktura', slug = 'manufaktura'
WHERE name = 'Manufactura';

INSERT INTO roaster_aliases (roaster_id, alias, alias_norm)
SELECT id, 'Manufactura', 'manufactura' FROM roasters WHERE name = 'Manufaktura'
ON CONFLICT (alias_norm) DO NOTHING;
