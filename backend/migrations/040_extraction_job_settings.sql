-- 040 (#169): extraction_jobs remembers how it was started.
--
-- `POST /api/admin/jobs/:id/resume` called `runWorker({ jobId, spendCapUsd })`
-- and nothing else, so `includeImages` fell back to its `true` default and
-- `limit` to 20 — silently converting a paused text-only job into an images-on
-- one with a fresh budget of photos, against Radu's standing text-only-first
-- rule (CLAUDE.md §10). The job row had no way to say otherwise because it
-- stored neither value.
--
-- `include_images` defaults to FALSE, not TRUE: the default here is what a row
-- written before this migration gets, and every historical job was created by
-- the daily text-only routine. Defaulting to TRUE would retroactively claim
-- those 54 jobs sent images. The route still defaults an *unspecified*
-- includeImages to true, unchanged — that is the API's contract, and it always
-- writes the real value now.
--
-- `photo_limit` is nullable: NULL means "not recorded" (pre-migration rows),
-- and resume falls back to the route's own default rather than inventing one.

ALTER TABLE extraction_jobs
  ADD COLUMN IF NOT EXISTS include_images BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS photo_limit    INT;
