-- 014_roaster_countries.sql — populate roasters.country_id, fixing #38
-- ("every coffee shows an unidentified roaster country").
--
-- 005_vocab_seed.sql seeded roasters as (name, slug) only, never country_id,
-- so `coffees.roaster_country_id` (worker.js copies it from `roaster.country_id`
-- at adjudication time — see buildCoffeeColumnUpdates) has been NULL for every
-- coffee since #35 shipped.
--
-- IMPORTANT — this is NOT sourced from the product brief. Verified directly
-- against `word/document.xml`: the brief's roaster list is just
-- "<name> (<purchase count>)" pairs, and the two "Countries list" sections are
-- flat country tallies (also swapped-heading, see 005's header comment) with
-- no per-roaster pairing at all. Radu's own brief (para 21) says "guess only
-- very close matches and prompt me to validate anything else" — so rather than
-- pattern-match roaster names to countries, every mapping below was verified
-- via a live web search against each roaster's own site / a roaster directory
-- (kofio.co, europeancoffeetrip.com, etc. — most of these ~80 names turn out
-- to be small Central/Eastern European microroasters carried by kofio.co, a
-- Czech specialty-coffee marketplace, which also explains why "Kofio" itself
-- is in the roaster list). Roasters with no confident single-country match
-- (ambiguous same-name brands in multiple countries, or no result at all) are
-- deliberately left NULL rather than guessed: Roastlab coffee roasters,
-- September Coffee, Typika (genuinely dual CZ/PL), Hydrangea Coffee Roasters,
-- Punkt. coffee, Radical Coffee, Ahiya Roasters, Kawa, Legendary Everyday.
-- These can still resolve per-coffee from a city mention in the caption text
-- (normalize.js's resolveCityCountry) even with country_id left NULL here.
--
-- Six countries turned up that 005_vocab_seed.sql never seeded (its roaster-
-- country set came from the brief's own, evidently incomplete, tally):
-- Italy, Austria, Sweden, Finland, Slovenia, South Korea. All six are
-- roaster-only (is_origin false) since none appear in the origin-country list.

INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Italy', 'IT', false, true, 'country'),
  ('Austria', 'AT', false, true, 'country'),
  ('Sweden', 'SE', false, true, 'country'),
  ('Finland', 'FI', false, true, 'country'),
  ('Slovenia', 'SI', false, true, 'country'),
  ('South Korea', 'KR', false, true, 'country')
ON CONFLICT (name) DO NOTHING;

UPDATE roasters r
SET country_id = c.id
FROM (VALUES
  ('DAK Coffee Roasters', 'Netherlands'),
  ('The naughty dog', 'Czech Republic'),
  ('The Coffee Collective', 'Denmark'),
  ('People Possession', 'France'),
  ('Father''s Coffee Roastery', 'Czech Republic'),
  ('Doubleshot', 'Czech Republic'),
  ('Coffea Circulor', 'Norway'),
  ('BirdSong Coffee', 'Czech Republic'),
  ('Beansmith''s', 'Czech Republic'),
  ('Fiftybeans', 'Czech Republic'),
  ('Rocket Bean Roastery', 'Latvia'),
  ('Nordbeans', 'Czech Republic'),
  ('Concept Coffee Roasters', 'Slovakia'),
  ('The Barn', 'Germany'),
  ('Coffeein', 'Slovakia'),
  ('Candycane Coffee', 'Czech Republic'),
  ('Manhattan Coffee Roasters', 'Netherlands'),
  ('Nomad Coffee', 'Spain'),
  ('Dos Mundos', 'Czech Republic'),
  ('Rebelbean', 'Czech Republic'),
  ('Tribes of Mokha Roastery', 'Czech Republic'),
  ('Square Mile', 'United Kingdom'),
  ('Sprout Coffee Roasters', 'Netherlands'),
  ('Poppy Beans', 'Czech Republic'),
  ('HAYB Speciality Coffee', 'Poland'),
  ('Respekt Coffee', 'Czech Republic'),
  ('Not Another Boring Roastery', 'Czech Republic'),
  ('Mia Coffee Roastery', 'Czech Republic'),
  ('BOO Modern Coffee', 'Belgium'),
  ('Tao Coffee', 'Czech Republic'),
  ('Kofio', 'Czech Republic'),
  ('Tanat Coffee', 'France'),
  ('Kaffa', 'Slovakia'),
  ('Blind Monkey', 'Ireland'),
  ('Gust Specialty Coffee', 'Belgium'),
  ('Lot Roastery', 'Slovakia'),
  ('Krok', 'Czech Republic'),
  ('Oh My Bean Roastery', 'Czech Republic'),
  ('Kmen Coffee Roasters', 'Czech Republic'),
  ('Industra Coffee', 'Czech Republic'),
  ('Guido', 'Romania'),
  ('Keen Coffee', 'Netherlands'),
  ('Maggma Beans', 'Sweden'),
  ('Man vs Machine', 'Germany'),
  ('Momos Coffee', 'South Korea'),
  ('Right Side', 'Spain'),
  ('Siemasu', 'Finland'),
  ('A.M.O.C', 'Netherlands'),
  ('Aliena', 'Italy'),
  ('April', 'Denmark'),
  ('Bani Beans', 'Slovenia'),
  ('Bonanza', 'Germany'),
  ('Brewing Dealers', 'Spain'),
  ('Drop Coffee Roaster', 'Sweden'),
  ('Elbgold', 'Germany'),
  ('Father Carpenter', 'Germany'),
  ('Fjord', 'Germany'),
  ('Friedhats', 'Netherlands'),
  ('FRUKT', 'Finland'),
  ('Gardelli', 'Italy'),
  ('Goat Story', 'Slovenia'),
  ('Goriffee', 'Slovakia'),
  ('GroundState', 'Ireland'),
  ('Jonas Reindl', 'Austria'),
  ('Kolibri', 'Netherlands'),
  ('La Cabra', 'Denmark'),
  ('Mabo', 'Romania'),
  ('Nero Scuro', 'Italy'),
  ('Nowhere', 'Italy'),
  ('ONYX', 'United States'),
  ('Process Coffee', 'United Kingdom'),
  ('Roastery 29', 'Romania'),
  ('Rumbaba', 'Netherlands'),
  ('RushRush', 'Belgium'),
  ('Sloane', 'Romania'),
  ('Sumo Coffee Roasters', 'Ireland'),
  ('Swerl', 'Sweden'),
  ('Three Marks Coffee', 'Spain'),
  ('Tim Wendelboe', 'Norway'),
  ('Uncommon', 'United Kingdom')
) AS v(roaster_name, country_name)
JOIN countries c ON c.name = v.country_name
WHERE r.name = v.roaster_name AND r.country_id IS NULL;

-- Backfill existing coffees rows: worker.js only copies roaster_country_id
-- from roasters.country_id at adjudication time, so rows adjudicated before
-- this migration are stuck at NULL until re-adjudicated. Fix them directly.
UPDATE coffees co
SET roaster_country_id = r.country_id
FROM roasters r
WHERE co.roaster_id = r.id
  AND r.country_id IS NOT NULL
  AND co.roaster_country_id IS NULL;
