-- 024_add_greece_roaster_country.sql — Radu: add Greece as a roaster country.
-- Roaster-only (is_origin false) — Greece roasts but doesn't grow coffee.
-- Mirrors 021 (Hong Kong) / 023 (Japan); ON CONFLICT keeps it idempotent.
INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Greece', 'GR', false, true, 'country')
ON CONFLICT (name) DO NOTHING;
