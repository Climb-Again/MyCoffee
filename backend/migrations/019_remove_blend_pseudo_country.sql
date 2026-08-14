-- 019_remove_blend_pseudo_country.sql — Radu: "Blend" is not a country.
-- A blend means MULTIPLE real origin countries, not a country named "Blend".
-- The legacy 'Blend' pseudo-country (004_vocab.sql, kind='pseudo') let a bag
-- resolve to a single fake "Blend" origin and showed up in the origin-country
-- picker. Nothing references it — verified 0 coffees (origin_country_ids /
-- roaster_country_id), 0 roasters.country_id, 0 farms.country_id — so remove it
-- entirely. is_blend is now derived purely from having >1 origin country
-- (vocab.js computeIsBlend). Delete any aliases first in case the FK isn't
-- ON DELETE CASCADE.
DELETE FROM country_aliases
WHERE country_id IN (SELECT id FROM countries WHERE kind = 'pseudo' AND name = 'Blend');

DELETE FROM countries WHERE kind = 'pseudo' AND name = 'Blend';
