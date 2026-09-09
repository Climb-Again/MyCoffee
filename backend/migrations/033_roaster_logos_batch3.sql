-- 033: roaster logos, batch 3 (Radu, 2026-09-07 — "2 more logos").
--
-- WatchHouse + BOO Modern Coffee already have blurbs (migration 030); now they
-- get logos too. Files renamed from supplied names to the seeded slug stem;
-- logo_url points at the PUBLIC repo's raw URL (web-only, no cache).
-- Idempotent: IS DISTINCT FROM, keyed by verified slug.

UPDATE roasters SET logo_url = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/watchhouse.png'           WHERE slug = 'watchhouse'         AND logo_url IS DISTINCT FROM 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/watchhouse.png'; -- WatchHouse
UPDATE roasters SET logo_url = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/boo-modern-coffee.webp'   WHERE slug = 'boo-modern-coffee' AND logo_url IS DISTINCT FROM 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/boo-modern-coffee.webp'; -- BOO Modern Coffee
