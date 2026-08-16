-- 023_add_japan_roaster_country.sql — Radu: add Japan as a roaster country (#63).
-- Roaster-only (is_origin false) — Japan roasts but doesn't grow coffee.
-- Mirrors 021 (Hong Kong) / 017 (Switzerland); ON CONFLICT keeps it idempotent.
INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Japan', 'JP', false, true, 'country')
ON CONFLICT (name) DO NOTHING;
