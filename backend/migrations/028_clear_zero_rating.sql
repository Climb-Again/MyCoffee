-- 028: clear the one rating of 0 that predates #123's envelope fix.
--
-- Coffee `4dBosHoqKJ89ABPeZgGVEg` (photo `e8INhGjYhczmETMEU9BxEg`) was added on
-- 2026-09-03 through the Add Coffee wizard and stored `rating = 0.0`. #123 made
-- `inRatingScale` exclusive at the floor so this can never be parsed again, but
-- the existing row cannot self-heal, for two independent reasons:
--
--   1. The wizard (`POST /api/coffees`) writes an `accepted` resolution
--      directly — it never produces `field_candidates` — so a re-adjudication
--      pass emits no key for `rating` at all, and #49's logic correctly
--      distinguishes "never voted on this pass" from "voted absent" and leaves
--      the column alone. Verified: `POST /api/admin/adjudicate` over all 411
--      photos changed nothing on this coffee.
--   2. That write sets `field_resolutions.locked = true, decided_by = 'human'`
--      — PLAN.md §1's invariant that no later pass overrides a human decision.
--      So the data currently asserts Radu confirmed a rating of 0. He did not;
--      it came from a stray digit via the old inclusive floor.
--
-- Hence both halves below. Clearing the column without deleting the locked
-- resolution would leave the false "human confirmed 0" claim in place and let a
-- later `applyResolutionsToCoffee` write the 0 straight back.
--
-- Idempotent: both statements are no-ops once applied.

DELETE FROM field_resolutions
 WHERE field = 'rating'
   AND (value = '0'::jsonb OR value = '0.0'::jsonb)
   AND photo_id IN (SELECT id FROM photos WHERE public_id = 'e8INhGjYhczmETMEU9BxEg');

UPDATE coffees
   SET rating = NULL, updated_at = now()
 WHERE public_id = '4dBosHoqKJ89ABPeZgGVEg'
   AND rating = 0;
