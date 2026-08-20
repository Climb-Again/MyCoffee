-- 025_add_photo_rotation.sql — persisted per-coffee photo rotation (#73, the
-- backend half of #57). Display-only: the stored display/thumb/ocr assets are
-- never re-encoded, the client applies the quarter-turns when rendering.
--
-- On `coffees`, not `photos`, deliberately: every read path the app uses
-- (toCompactCoffee, the detail route, the delta sync's updated_at watermark) is
-- already a coffees-row projection and the app never sees a photos row.
ALTER TABLE coffees ADD COLUMN IF NOT EXISTS rotation_quarter_turns SMALLINT NOT NULL DEFAULT 0;

ALTER TABLE coffees DROP CONSTRAINT IF EXISTS coffees_rotation_quarter_turns_check;
ALTER TABLE coffees ADD CONSTRAINT coffees_rotation_quarter_turns_check
  CHECK (rotation_quarter_turns BETWEEN 0 AND 3);
