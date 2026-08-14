-- 018_add_cameroon_origin_country.sql — Radu: add Cameroon as an origin country.
-- Cameroon grows coffee (Arabica in the west highlands, Robusta elsewhere) but
-- isn't a roaster country here, so is_origin true / is_roaster false. ON CONFLICT
-- keeps it idempotent.
INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Cameroon', 'CM', true, false, 'country')
ON CONFLICT (name) DO NOTHING;
