-- 015_fix_uncommon_roaster_country.sql — #48(a)
-- Correct the "Uncommon" roaster country: United Kingdom → Netherlands.
--
-- #38's 014_roaster_countries.sql guessed Uncommon = United Kingdom. Root cause
-- is a roaster name collision: a UK "Uncommon Coffee Roasters" and the Amsterdam
-- "Uncommon" share a name and collapsed into one vocab row (id 89), which #38
-- guessed as UK. Radu's actual purchases are unambiguously the Amsterdam one —
-- every caption reads "Prăjitorie: Uncommon (Amsterdam, Olanda)". Correct the
-- single roaster row to Netherlands.
--
-- Then force-refresh the denormalized `roaster_country_id` on its coffees.
-- worker.js copies roaster_country_id from roasters.country_id only at
-- adjudication time (buildCoffeeColumnUpdates), so already-adjudicated rows are
-- stuck at the old UK value — 014's backfill only touched NULLs, so a plain
-- re-run would skip them. Use IS DISTINCT FROM so this is idempotent (re-running
-- the migration set is a no-op once every Uncommon coffee already reads NL) and
-- covers both the UK rows and any that were left NULL.
--
-- `updated_at` is bumped on exactly the rows that change, so the iOS delta sync
-- (GET /api/snapshot?since=…, which filters `co.updated_at > since`) actually
-- ships the corrected rows to the app on its next sync — without a bump the
-- client would keep showing the stale country until a full re-sync.

UPDATE roasters
SET country_id = (SELECT id FROM countries WHERE name = 'Netherlands')
WHERE name = 'Uncommon';

UPDATE coffees co
SET roaster_country_id = r.country_id,
    updated_at = now()
FROM roasters r
WHERE co.roaster_id = r.id
  AND r.name = 'Uncommon'
  AND co.roaster_country_id IS DISTINCT FROM r.country_id;
