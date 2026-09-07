-- 031: assign roaster countries for 7 roasters (Radu, 2026-09-07 content intake)
-- + flag Indonesia and Thailand as roaster countries (#115).
--
-- Indonesia (13) and Thailand (26) already exist as ORIGIN countries; Radu now
-- has roasters based there (Livingfoodlab / Koff & Bun), so they become dual
-- origin+roaster countries (is_roaster=true, is_origin unchanged). This is NOT
-- the Greece/Japan pattern (021/023/024 INSERT a new roaster-only row) — the
-- rows already exist, they just need the flag.
--
-- The roaster-country decode fix (iOS Vocab.swift CodingKeys) means these now
-- render on the roaster page. Reaches the app via the snapshot — no app build.
-- Idempotent: every UPDATE is a no-op once applied (IS DISTINCT FROM, keyed by
-- id/slug). Ids verified live against /api/snapshot.

UPDATE countries SET is_roaster = true
  WHERE id IN (13, 26) AND is_roaster IS DISTINCT FROM true; -- Indonesia, Thailand

UPDATE roasters SET country_id = 13 WHERE slug = 'livingfoodlab'     AND country_id IS DISTINCT FROM 13; -- Indonesia
UPDATE roasters SET country_id = 49 WHERE slug = '17g-coffee'        AND country_id IS DISTINCT FROM 49; -- Switzerland
UPDATE roasters SET country_id = 26 WHERE slug = 'koff-bun'          AND country_id IS DISTINCT FROM 26; -- Thailand
UPDATE roasters SET country_id = 41 WHERE slug = 'monmouth'          AND country_id IS DISTINCT FROM 41; -- United Kingdom
UPDATE roasters SET country_id = 42 WHERE slug = 'radical-coffee'    AND country_id IS DISTINCT FROM 42; -- Romania
UPDATE roasters SET country_id = 38 WHERE slug = 'spojka'            AND country_id IS DISTINCT FROM 38; -- Slovakia
UPDATE roasters SET country_id = 37 WHERE slug = 'mere-black-coffee' AND country_id IS DISTINCT FROM 37; -- Poland
