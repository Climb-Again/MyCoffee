-- 042 (#197): the shortlist's retention clock starts when a coffee is ADDED,
-- not at its last visit.
--
-- Radu, 2026-09-12: "discard after 30d from being added to shortlist (since you
-- sync on server you have timestamp)". `saved_at` is bumped by every revisit
-- (it drives the "seen 2h ago" subtitle, #188), so retention measured from it
-- was wrong in both directions: a coffee he kept checking in on reset its own
-- clock and rode the list forever, while one he saw once and mentally
-- shortlisted fell off at exactly 10 days.
--
-- The server owns this timestamp, per his parenthetical — the client's copy is
-- a cache. `added_at` is set once on insert and deliberately NOT touched by the
-- ON CONFLICT DO UPDATE in routes/history.js.
--
-- Backfill: existing rows get `added_at = saved_at`, i.e. "as if he shortlisted
-- it at its last visit". That underestimates their age by at most the old
-- 10-day window, which is the safe direction — a row lives slightly longer
-- rather than being dropped on the first read after this deploy.

ALTER TABLE history
  ADD COLUMN IF NOT EXISTS added_at TIMESTAMPTZ;

UPDATE history SET added_at = saved_at WHERE added_at IS NULL;

ALTER TABLE history
  ALTER COLUMN added_at SET DEFAULT NOW(),
  ALTER COLUMN added_at SET NOT NULL;

-- Retention now reads added_at; saved_at keeps the ORDER BY for the list.
CREATE INDEX IF NOT EXISTS history_token_added_idx ON history (token_hash, added_at DESC);
