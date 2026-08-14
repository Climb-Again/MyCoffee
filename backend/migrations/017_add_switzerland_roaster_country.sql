-- 017_add_switzerland_roaster_country.sql — Radu: add Switzerland as a roaster country.
-- Roaster-only (is_origin false) — Switzerland roasts but doesn't grow coffee.
-- Mirrors 014's roaster-country additions; ON CONFLICT keeps it idempotent.
INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Switzerland', 'CH', false, true, 'country')
ON CONFLICT (name) DO NOTHING;
