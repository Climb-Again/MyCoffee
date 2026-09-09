-- 032: roaster logos, batch 2 (Radu, 2026-09-07 — "update also logos in git").
--
-- Four more roaster logos added to ops/roaster-assets/logos/, renamed here from
-- their supplied names to the seeded slug stem. logo_url points at the PUBLIC
-- repo's raw URL (web-only, no cache — Radu's standing call). Pillow was not
-- available in this session, so onyx/origo/sumo keep their png/jpeg source
-- format (fine: web-only, uncached, AsyncImage decodes all three); a later
-- normalize-logos.py sweep can convert them to WebP without changing the slug.
--
-- Idempotent: IS DISTINCT FROM, keyed by verified slug.

UPDATE roasters SET logo_url = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/father-s-coffee-roastery.webp' WHERE slug = 'father-s-coffee-roastery' AND logo_url IS DISTINCT FROM 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/father-s-coffee-roastery.webp'; -- Father's Coffee Roastery
UPDATE roasters SET logo_url = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/onyx.png'                      WHERE slug = 'onyx'                      AND logo_url IS DISTINCT FROM 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/onyx.png'; -- ONYX
UPDATE roasters SET logo_url = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/origo.jpeg'                    WHERE slug = 'origo'                     AND logo_url IS DISTINCT FROM 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/origo.jpeg'; -- Origo
UPDATE roasters SET logo_url = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/sumo-coffee-roasters.png'      WHERE slug = 'sumo-coffee-roasters'      AND logo_url IS DISTINCT FROM 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/sumo-coffee-roasters.png'; -- Sumo Coffee Roasters
