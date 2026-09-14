-- 041 (#129): stop retrying a photo whose OCR keeps coming back illegible.
--
-- `backfillOcrText` selects on `raw_description NOT LIKE '%OCR text%'`, and
-- `appendOcrTextToCoffee` returns false without writing when the transcription
-- is blank. So a permanently illegible photo never leaves the candidate set: it
-- re-enters at the top of every `ORDER BY c.id` page, burns a paid flash-lite
-- call and occupies one slot of every batch, forever. Coffee id 7 did exactly
-- that in 20 consecutive batches during #126's backfill.
--
-- Three attempts, not one, so a transient model blip or a quota error doesn't
-- permanently write off a photo that is actually fine. The counter RESETS on a
-- successful append (worker.js), and `retryExhausted: true` on the endpoint
-- clears it so a better photo or a better model can be tried deliberately.

ALTER TABLE photos
  ADD COLUMN IF NOT EXISTS ocr_attempts INT NOT NULL DEFAULT 0;

-- Seed the two photos already known to be untranscribable (#129's own note),
-- so the first run after this migration doesn't have to rediscover them at
-- the cost of three more calls each. Idempotent.
-- (Those two ids are COFFEE public_ids -- what backfillOcrText's error list
-- reports -- so this joins through coffees rather than matching photos.public_id,
-- which would silently update nothing.)
UPDATE photos p
   SET ocr_attempts = 3
  FROM coffees c
 WHERE c.photo_id = p.id
   AND c.public_id IN ('VxGMXHg8TBKZCaDBVEZw2w', 'ESVarM-49a21FnMXw36MqA')
   AND p.ocr_attempts < 3;
