-- 044 (#126c): a captioned photo gets ONE image pass, not zero.
--
-- The rule that caused the gap: `shouldUseImage(photo, includeImages)` sends
-- the image only when the job asks for images, or when the photo is
-- `awaiting_text`. A photo that arrives with ANY caption text lands in
-- `text_received`, and the daily routine runs text-only first and escalates to
-- images only if IMAGE-ONLY photos remain — which they never do. So a captioned
-- photo is extracted from its caption forever and its bag is never read.
-- Measured across 413 live coffees: zero carried an OCR text block.
--
-- Radu, 2026-09-14, asked for the full re-extraction ("#126 all"); this column
-- is the half that stops it silently re-accruing on every NEW bag.
--
--   needs_image_pass  set by the worker when a text-only pass leaves core
--                     fields unresolved. Makes `shouldUseImage` return true on
--                     the next claim, whatever the job's own flag says.
--   image_pass_at     set the first time a pass actually sends the image. The
--                     hard stop: escalation is offered ONCE per photo, so a bag
--                     whose fields are genuinely absent (a blurb with no price
--                     printed anywhere) cannot burn a vision call every run.
--
-- Backfilled as "already had its pass" for every photo that carries an OCR
-- text block — those demonstrably went through image mode — so enabling this
-- does not re-bill work already done.

ALTER TABLE photos
  ADD COLUMN IF NOT EXISTS needs_image_pass BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS image_pass_at    TIMESTAMPTZ;

UPDATE photos p
   SET image_pass_at = COALESCE(p.image_pass_at, now())
  FROM coffees c
 WHERE c.photo_id = p.id
   AND p.image_pass_at IS NULL
   AND c.raw_description LIKE '%OCR text%';
