# Lane: Data extract + validate

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## ⚠ Correction (2026-08-01): "done, on `main`" below is NOT on the real `main`

This session was harness-assigned to develop on `claude/peaceful-mccarthy-rwi2ql`
(a fixed branch name for this session, not something this lane chose). Verified
directly: `git rev-parse main origin/main` are identical (`0ad0023`), and that
commit is `git show origin/main:status/BACKLOG.md` — which still lists #12/#13/#34
as `ready`, #17/#18 as `ready`/`blocked`, #10 as `human` — i.e. **none of the
"consolidated onto main" work below, from any lane, is actually on the real
shared `main`.** It all lives only on this `claude/*` branch. Every prior
"branch `main`" note in this file (and the matching ones in `backend.md` /
`ios-shell.md` / `ios-ux.md` / `publish.md`) was written by a session under the
same branch-name confusion this file's own "Superseded / to delete" section
describes for `o8kxxo`/`toj6mv`/`n4nt4i` — it's the identical failure mode one
level up: not "three branches redid the same work", but "one branch believes
itself to be `main` and says so in its own status notes".

This is not something a lane session can fix by pushing harder — `git push` is
restricted to this one branch this session (`claude/peaceful-mccarthy-rwi2ql`;
"never push to a different branch without explicit permission"). **Someone
with authority to push to `origin/main` needs to fast-forward/merge this
branch in**, the same way `status/README.md`'s "Integrate before you start"
rule already prescribes for stranded `claude/*` work. Until that happens,
treat every "done, on `main`" note across all `status/*.md` files as "done, on
`claude/peaceful-mccarthy-rwi2ql`" instead.

## Claimed

_none_

## Done

- [2026-07-31 07:30 UTC] #12 + #13 + #34 — **consolidated onto `main`** from three
  stranded fired-session branches that each redid the same work in isolation because
  `main` never advanced (see the "un-integrated prior work" rule in `status/README.md`).
  Rebuilt cleanly on current `main` and validated end-to-end against a real Postgres
  16 (migrations 001→007 applied, fx seed loaded, full `node --test` suite 59/59 green):
  - **#12 — `backend/migrations/005_vocab_seed.sql`** (from `claude/peaceful-mccarthy-o8kxxo`,
    orig `63598f7`). Seeds against the real `004_vocab.sql` schema: **42 countries**
    (26 origin), **89 roasters**, 47 country aliases, 101 roaster aliases. Values
    extracted from `brief/MyCoffee app.docx` in `Climb-Again/mycoffee-private` — the
    docx itself is never copied here (public-repo rule).
  - **#13 — `backend/src/lib/normalize.js` + `fuzzy.js` + tests** (o8kxxo, orig `119362c`).
    Pure parsers/matchers; `normalize.test.js` + `fuzzy.test.js` table-driven, all green.
    This branch's API is now the contract downstream (#14 vocab.js, extraction) builds on:
    `normalize` exports `normalizeVocabString/foldDiacritics/parseNumber/parseAltitude/`
    `parsePrice/parseWeight/parseRating/parseDate/parseProfile/parseFarm/resolveCityCountry`;
    `fuzzy` exports `levenshteinDistance/normalizedLevenshteinSimilarity/trigramSimilarity/matchVocab`.
  - **#34 — `ops/fx_rates_seed.sql` + `ops/seed-fx-rates.mjs`** (o8kxxo, orig `79f654f`)
    **plus `backend/src/lib/fx.js` + `test/fx.test.js`** (from `claude/peaceful-mccarthy-toj6mv`,
    orig `eb2ffa4` — the only branch with the tested conversion helper). Seed loads
    **1510 rows** (10 currencies × 151 ECB monthly averages). **Inversion direction
    verified live** against `BACKLOG.md`'s anchors — RON `rate_to_eur`: 2015-01 =
    `0.222845`, 2019-06 = `0.211640`, 2024-06 = `0.200935` (i.e. ~0.22, not ~4.49);
    all 10 currencies land in sane EUR ranges. The seed is applied manually
    (`psql -f ops/fx_rates_seed.sql`), **not** in the auto-run migration chain, per
    006's own comment.
  - `fx.js` satisfies the `fx.js` half of backend #14 (data lane owns `src/lib/fx.js`
    per the ownership table); #14 now needs only `vocab.js`. — branch `main`
    (see correction above: really `claude/peaceful-mccarthy-rwi2ql`)

- [2026-08-02 PENDING-SHA] #20 — **`ops/mycoffee_export.py`** + `ops/test_mycoffee_export.py`
  (29/29 green) + `ops/README.md`. Two-phase Mac exporter/uploader for the
  "Coffees" Photos album against #19's `routes/photos.js`
  (`POST /api/photos/manifest` then `PUT /api/photos/:sourceId/image`).
  Pure logic (manifest-entry shaping incl. always-null `caption` since
  Photos.app has no field distinct from `.description`; ≤200-entry batching;
  an on-disk `(size, mtime)` state cache so a repeat run skips `sips` for
  every unchanged photo; HTTP retry/backoff `(2,5,15,45,120)s` that never
  retries a deterministic 4xx) is unit-tested with no macOS dependency —
  `osxphotos` (Photos-library read) and `sips` (HEIC→JPEG, matching the
  server's `ocr` 2048px/q85 derivative) are isolated behind lazy imports
  specifically so tests never need them installed. Key invariant documented
  in the README: `contentSha256` in the manifest must be the hash of the
  **exact bytes later PUT** (the post-`sips` JPEG), not the original file,
  because the server 409s (`sha256_mismatch`) on any mismatch against a
  previously-declared `photos.content_sha256`.
  **Not verified end-to-end** — this sandbox has no macOS runner and no
  access to a real Photos library, so the PLAN.md §8 20-photo gate (run,
  confirm derivatives, confirm a re-run is a no-op) is still owed by whoever
  next has a Mac. Checklist is in `ops/README.md`. Backend `npm test` still
  93/93 green (unaffected — this lane touched only `ops/**`). — branch
  `claude/peaceful-mccarthy-3f480y`

- [2026-08-01 ebfce55] #14 — **`backend/src/lib/vocab.js`** + 24 new tests
  (`test/vocab.test.js`, 86/86 green). Resolution against the `004_vocab.sql`
  tables: `resolveVocab` (exact `alias_norm` lookup, fuzzy fallback via
  `fuzzy.js`'s `matchVocab`, so a fuzzy accept still needs the unique-candidate +
  margin guard — covered the mandatory `Kofio`/`Kolibri` and `Father's Coffee
  Roastery`/`Father Carpenter` negative cases at this layer too, not just in
  `fuzzy.test.js`); `resolveOriginCountries` (splits `/`/`,`-separated multi-origin
  text, e.g. `Colombia / Brazil`, into ids — origin isn't single-valued, PLAN.md
  §1); `computeIsBlend` + `validateOriginCountryIds` (the array-referential-
  integrity check the migration 004 comment says belongs here, since Postgres
  can't FK-constrain `origin_country_ids` array elements); `buildCityMap` +
  `resolveCity` (merges `cities` + `city_aliases` into one normalized-name map,
  delegates the actual ambiguous-never-resolves rule to `normalize.js`'s existing
  `resolveCityCountry`); and four thin DB loaders (`loadCountryVocab`,
  `loadRoasterVocab`, `loadFarmVocab`, `loadCityVocab`) that shape query results
  for the pure functions above, same query-elsewhere/logic-here split as
  `fx.js` — kept the resolution logic testable without a live Postgres. Unblocks
  backend #21 (needs 11, 14 — both now done; flipped `blocked`→`ready` in the same
  commit). — branch `claude/peaceful-mccarthy-rwi2ql` (not `main` — see correction
  above)

## Superseded / to delete

The three source branches below are now fully consolidated onto `main` and hold no
unique un-landed work. Safe for Radu to delete once this lands:
`claude/peaceful-mccarthy-o8kxxo`, `claude/peaceful-mccarthy-toj6mv`,
`claude/peaceful-mccarthy-n4nt4i` (n4nt4i was a strict subset — #12 + #13 only, no fx).

## Abandoned

_none_
