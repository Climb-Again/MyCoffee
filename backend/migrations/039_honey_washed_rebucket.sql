-- 039 (#208): re-bucket the remaining honey-only coffees to Washed.
--
-- `parseProfile` (src/lib/normalize.js) folds a honey-ONLY mention to Washed and
-- a honey+other-method hybrid to Experimental (Radu, 2026-08-29). The rule has
-- been shipped for a while; these three rows were classified before it and
-- cannot self-heal — `POST /api/admin/adjudicate` only re-canonicalizes already
-- stored `field_candidates` (see #124), and the rules voter's frozen output is
-- what produced the stale value in the first place.
--
-- The target list is a LIVE MEASUREMENT, re-taken 2026-09-14 against production
-- rather than reused from the 2026-08-29 write-up, which said "all 25 honey
-- coffees". Feeding each coffee's real stored raw text (rawTitle + rawCaption +
-- rawDescription, exactly what worker.js's buildRawText() assembles) through the
-- current parseProfile today gives Washed for only **3 of those 25**. The other
-- 22 have since had richer description/OCR text backfilled onto them and now
-- carry either a genuine second process beside the honey word ("Procesare: Black
-- Honey, Carbonic Maceration") or a roaster-labelled Procesare naming a
-- different method entirely (a coffee *titled* "Hydro Honey" whose structured
-- field reads "Procesare: Experimental"). Both correctly stay out of Washed —
-- there the honey word is part of a product name or a flavour note, not the
-- process.
--
-- Hence three explicit public_ids and NOT a `profile_detail ILIKE '%honey%'`
-- scan: a bare "Honey" and a real hybrid store the identical literal in
-- profile_detail, so a pattern-based WHERE would flip all 22 genuine
-- non-Washed rows too.
--
-- `profile_detail` keeps the honey literal verbatim — that is what renders the
-- "Washed (Honey)" bracket (#209) — so only `profile_id` moves.
--
-- Idempotent: the `profile_id <> washed` guard makes a re-run a no-op.
-- Human-safe: skips any coffee whose photo carries a locked, human-decided
-- `field_resolutions` row for `profile` (PLAN.md §1's invariant). None of the
-- three has one today; the guard is here so that stays true if one gains one
-- between this file being written and being applied.

UPDATE coffees c
   SET profile_id = (SELECT id FROM profiles WHERE slug = 'washed'),
       updated_at = now()
 WHERE c.public_id IN (
         'NMjnDjbOn6QA9a3yOVPC2w',
         'eRZVF_rb6aUep2PPchz3lQ',
         'e8dZ8dMwJIgFkoCxzWtlcQ'
       )
   AND c.profile_id IS DISTINCT FROM (SELECT id FROM profiles WHERE slug = 'washed')
   AND NOT EXISTS (
         SELECT 1
           FROM field_resolutions fr
          WHERE fr.photo_id = c.photo_id
            AND fr.field = 'profile'
            AND fr.locked = true
            AND fr.decided_by = 'human'
       );
