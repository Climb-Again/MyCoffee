-- 021_add_hong_kong_roaster_country.sql — Radu: add Hong Kong as a roaster country.
-- Roaster-only (is_origin false) — Hong Kong roasts but doesn't grow coffee.
-- Mirrors 017's roaster-country addition; ON CONFLICT keeps it idempotent.
INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Hong Kong', 'HK', false, true, 'country')
ON CONFLICT (name) DO NOTHING;
