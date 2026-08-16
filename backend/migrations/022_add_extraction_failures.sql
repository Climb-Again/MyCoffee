-- 022_add_extraction_failures.sql — stop the worker looping forever on a photo
-- that always fails (#64). runWorker re-claims a failed photo immediately (its
-- lease is released in the catch), and photos_done only counts successes, so a
-- permanently-failing photo (e.g. an image-only photo with no text, which
-- returns Gemini 400 in text-only mode) makes the worker spin forever holding
-- the extraction advisory lock — blocking every other job. Track per-photo
-- failures so claimBatch can exclude a photo after N attempts. Default 0, so
-- existing photos (including today's stragglers) start eligible again — which
-- also lets the one-off image-OCR run pick them up.
ALTER TABLE photos ADD COLUMN IF NOT EXISTS extraction_failures INT NOT NULL DEFAULT 0;
