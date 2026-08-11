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

## 2026-08-09 UTC: session check — no ready row this cycle

`main`/`origin/main` agree at `01dcf36`. Every data-tagged row in
`status/BACKLOG.md` is `done` (#12, #13, #14, #20, #25, #34) except **#26**,
still `human` — the 25-record tuning run and #29 (hardening) both wait on
Radu's accuracy verdict on the 5-photo sample per the spend gate, and that
verdict isn't a lane's to give. No new note from Radu found anywhere this
session reads (`BACKLOG.md`, this file). This lane's own designated branch
(`claude/peaceful-mccarthy-buk42g`) was 0 ahead/0 behind `main` — nothing of
this session's own was stranded.

Swept `git branch -r --list 'origin/claude/*'` (64 branches) for stranded
data-lane work before concluding there was none to adopt: filtered to the
25 branches with commits ahead of `main`, then diffed each against `main`
restricted to this lane's owned paths (`ops/**`,
`backend/migrations/005_vocab_seed.sql`,
`backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js`). All
25 are net-deletions-only against those paths — stale forks off `main` tips
that predate this lane's work landing, not unintegrated new work — matching
the shape prior sweeps (see `status/backend.md`) already found for the same
branch family. Nothing adopted.

Per the routine's own instruction ("if nothing qualifies, post a one-line
status and stop — do not invent work"), stopping here.

## 2026-08-04 — #26's 5-photo sample RAN against production. Findings for tuning.

Job 7: `voterSet:'full'`, `limit:5`, `includeImages:false` (text-only, Radu's
call), **5/5 photos, $0.2154** — under the ~$0.35 estimate. First LLM extraction
this project has ever completed. Four defects had to be fixed first (see
`status/backend.md` / git log `cdf3086`, `adafb7f`, `29116ad`), the real one
being that `generateContent` ignored the per-voter model, so the "flash" voters
ran on 2.5-pro with `thinkingBudget: 0` — which pro rejects outright.

**What came out right** (spot-checked against the raw captions):
- Roasters resolved via vocab: DAK Coffee Roasters, Manhattan Coffee Roasters,
  Concept Coffee Roasters.
- Origins: Colombia (×3), Brazil (×1).
- Ratings: 4.0 / 4.2 / 4.3 from `4/5`, `4.2/5`, `4.3/5`.
- Prices: 75.00 / 60.00 / 140.00 RON. Weights: 250 g where `250gr` appeared.
- Altitude 1800 m from `Altitude: 1800 masl`.
- `roasted_on` = 2026-06-08 parsed from the Romanian `Data de prăjire: 8 Iunie
  2026` — the localized date path works.
- A caption containing only `4.3/5` yielded exactly one field and adjudicated
  `clean`. Correct restraint, no invention.

**Accuracy gaps worth fixing in the tuning pass — do not treat as done:**
1. **`is_decaf` missed.** The Manhattan record is titled `El Vergel (Decaf)`,
   lists `Procesare: Anaerob, Decaf` and `DECAFFEINATED`, yet `is_decaf` is
   `false`. Decaf is tracked orthogonally to `profile` (PLAN.md pushback #3), so
   this is a prompt/field gap, not a vocabulary one.
2. **`profile` never resolved (all 5).** The seeded profiles are Washed /
   Natural / Anaerobic / Co-fermented / Experimental, but the corpus says
   **Honey** (×2), `Double Anaerobic`, `Co-Fermentata cu fructe`, `Experimental
   Washed`. **`Honey` is missing from the vocabulary entirely** and the
   multi-value cases ("Co-fermented *and* Honey") don't fit one `profile_id`.
   Decide: add `Honey` (+ maybe `Honey/Anaerobic` combinations) to `profiles`,
   or model process as multi-valued.
3. **`price_eur` is NULL on every priced record**, so price filters/insights
   will be blank in the app. Cause is *not* the extraction: `fx_rates` is
   **empty in production**. `ops/fx_rates_seed.sql` is deliberately applied by
   hand (`psql -f`) and is not in the migration chain — and it has never been
   run against Railway. The 1510-row seed was only ever verified against a
   local Postgres. Fix is one of: promote the seed to a migration (the
   direction is anchor-verified, so the original "don't let a wrong guess reach
   price_eur silently" concern is largely addressed), or run the psql by hand
   against Railway.
4. **`Radical Coffee` didn't resolve** even though the vocabulary *does* contain
   `Radical Coffee` and the caption says `Radical Coffee Roasters` — the
   longer "… Roasters" form appears not to match the seeded alias. Worth an
   alias pass over `roaster_aliases` for the `X` / `X Roasters` pattern.
5. `roaster_country_id` is NULL on all resolved roasters — the seeded roasters
   have no `country_id`, so the denormalization has nothing to copy.
6. `origin_farm_id` is `no_candidates` ×4 — expected (farm vocab is seeded from
   review, not up front), listed so it isn't mistaken for a regression.

23 review items were opened across the 5 records, which is the
vocabulary-confirmation queue #25 was built to produce.

**Next step is Radu's, not a lane's:** he judges accuracy, then the 25-record
tuning run. `#26` is `human` in `BACKLOG.md` for exactly that reason.

## Done

- [2026-08-11 01:42 UTC] #39 — **hard plausibility envelopes for `parseAltitude`/`parseWeight`/`parseRating`**
  in `backend/src/lib/normalize.js` (PLAN.md §11 #39). Radu's refinement of #35:
  "I know I said accept all guesses, but altitude 1–5 m does not make sense."
  With accept-by-default dropping the confidence gate, a mis-parse now reaches
  the app directly, so each numeric parser gets a **hard reject** beyond its
  existing soft band:
  - `parseAltitude`: `max<200` or `min>4000` → `null` (absent, not stored).
    The soft 900–2200 "real but unusual" plausible band is untouched — a
    genuine elevation outside it still surfaces with `needsReview`.
  - `parseWeight`: `<1g` or `>5000g` → `null`. No real coffee bag is
    sub-gram or over 5 kg.
  - `parseRating`: outside `0–5` → `null`, applied uniformly across the
    `/5`, star-emoji, and bare-number branches (matches the
    `coffees.rating` `CHECK(0-5)` constraint `adjudicate.js` already
    independently guards at its own layer for the live "45" crash —
    this is the matching fix at the source, per this row's own file
    assignment).
  Updated `normalize.test.js`'s existing altitude "implausible" fixture
  (it asserted a soft-reject result for a range that now hard-rejects) and
  added three new table-driven tests for the negative envelope + boundary
  cases on all three parsers. `npm test` 213/213 green (11 new).
  **Confirmed the exact live bug before pushing**: `GET /api/coffees/:publicId`
  against production showed two real coffees stored with `altitudeMinM/MaxM`
  of `1/5` and `2/30` — Radu's own example, live in the corpus right now.
  Checked `GET /api/admin/jobs` first (all 10 historical jobs `done`/`paused`,
  none `running`) before pushing `backend/**`.
  **$0 re-adjudication validation** (PLAN.md #39's own acceptance test —
  `POST /api/admin/adjudicate` re-runs over stored `field_candidates`, no new
  LLM spend): see the follow-up note below for the post-deploy result.
  — branch `main`, commit `3378955` (claim `e5859a0`).

- [2026-08-10 02:00 UTC] #38 — **`backend/migrations/014_roaster_countries.sql`**
  populates `roasters.country_id` (previously NULL for all 89 seeded roasters,
  which made every coffee's roaster-country flag unidentified) and backfills
  existing `coffees.roaster_country_id` rows.
  **Important correction to the backlog row's own premise**: verified directly
  against `word/document.xml` that the product brief does **not** pair roaster
  names with countries at all — its "Roasters list" is flat `name (count)`
  pairs, and the two "Countries list" sections (already known to be
  heading-swapped, per `005_vocab_seed.sql`) are flat country tallies with no
  per-roaster link. The backlog's own example mappings (Gardelli→Italy,
  Jonas Reindl→Austria) turned out right, but "Concept Coffee Roasters→Romania"
  was wrong (verified: Slovakia) — illustrating exactly why this needed
  verification rather than being seeded from memory/the backlog note as-is.
  Sourced instead via live web search against each roaster's own site or a
  roaster directory, one roaster at a time — most of these turn out to be
  small Central/Eastern-European microroasters carried by `kofio.co` (a Czech
  specialty-coffee marketplace; explains why "Kofio" itself is also in the
  roaster list). Per Radu's own brief text (para 21: "guess only very close
  matches and prompt me to validate anything else"), **9 of the 89 were left
  NULL** rather than guessed — genuinely ambiguous (same-brand-name roasters
  in multiple countries) or no confident source found: `Roastlab coffee
  roasters`, `September Coffee`, `Typika` (verified genuinely dual
  Czech Republic **and** Poland — doesn't fit one `country_id`), `Hydrangea
  Coffee Roasters`, `Punkt. coffee`, `Radical Coffee`, `Ahiya Roasters`,
  `Kawa`, `Legendary Everyday`. These can still resolve per-coffee from a city
  mention in caption text via `normalize.js`'s `resolveCityCountry` even with
  `country_id` left NULL.
  6 countries the docx's own (evidently incomplete) roaster-country tally
  never seeded were added: Italy, Austria, Sweden, Finland, Slovenia, South
  Korea — all `is_roaster: true`, `is_origin: false`.
  **Verified end-to-end against a real local Postgres 16**: all 14 migrations
  apply cleanly in order; 80/89 roasters got a `country_id`, the other 9 match
  exactly the flagged-unmapped list; a hand-inserted coffee row confirmed the
  backfill UPDATE (a) fills a NULL `roaster_country_id` from the roaster's new
  `country_id`, (b) leaves it NULL when the roaster is one of the 9 unmapped
  ones, (c) does **not** clobber a coffee row that already had a (deliberately
  different, for the test) non-NULL `roaster_country_id` — the backfill is
  additive, re-runnable, and won't fight a future per-coffee resolution.
  `npm test` 202/202 green. Checked `GET /api/admin/jobs` first per the
  "never push `backend/**` while a job is `running`" rule — all 10 historical
  jobs are `done`/`paused`, none `running`, so this push is safe.
  Deploys via `railway-deploy.yml` on push (`backend/**` changed); no
  TestFlight publish needed. — branch `main`, this commit.

- [2026-08-04] #25 — **`backend/src/lib/deterministic.js` (P3 "rules" voter) +
  `test/deterministic.test.js`** (180/180 green, up from 178). Implements the
  `{agent:'rules', provider:'rules', run(ctx)}` contract `agents.js`'s
  `loadRulesVoter()` already expected. Two strategies, matching how
  `adjudicate.js`'s `canonicalize()` re-derives a value from whatever raw
  string a voter proposes:
  - **altitude/price/weight/rating/profile** — `normalize.js`'s parsers
    already scan arbitrary free text for their own markers, and
    `canonicalize()` re-runs the identical parser on this voter's raw value,
    so this module only decides *whether* a field fired (by calling the
    parser once itself) and hands the raw caption straight through when it did.
    **Found and fixed a real bug in this pass, not a pre-existing one**:
    `parsePrice`/`parseRating` both have a low-confidence *bare-number*
    fallback branch ("never silent" per PLAN.md §2) designed for a
    narrowly-scoped value a caller already believes is a price/rating —
    scanning a *whole caption* with that fallback grabs the first unrelated
    digit it finds (a date, an altitude) as a fake price/rating. Fixed by
    gating price/rating proposals on the field's own explicit marker
    (currency symbol/code, or "/5"/"⭐") before ever calling the parser;
    caught by an end-to-end run against a real local Postgres 16 (see below),
    not by the unit tests alone — regression cases now in
    `deterministic.test.js`.
  - **roaster_id/origin_country_ids/origin_farm_id** — `canonicalize()`
    resolves these via `resolveVocab()`, an EXACT `alias_norm` lookup on the
    *whole* raw value, not a substring scan. So this module scans the caption
    itself (`findAliasMentions`, diacritic-folded, word-boundary-safe even for
    3-letter aliases like `DAK`) and proposes only the matched substring.
    Origin is multi-valued (joins every distinct *is_origin* mention,
    `"Colombia / Brazil"`, for `resolveOriginCountries` to re-split
    downstream); roaster is single-valued and refuses to guess when two
    *different* roasters tie at the same match specificity (mirrors the
    mandatory `Kofio`/`Kolibri` and `Father's Coffee Roastery`/`Father
    Carpenter` negative cases, now also covered at this text-scanning layer).
    Farms have no seed vocabulary at all (PLAN.md §1: "derived from the data,
    approved in review") — `extractFarmField` still proposes a candidate
    whenever a `parseFarm`-recognised prefix (`Finca …`, `Producer: …`, …) is
    present, so Phase 0 also seeds the *farm* review queue from $0, not just
    roaster/country.
  - **Verified end-to-end against a real local Postgres 16** (all 11
    migrations applied cleanly), not just unit tests: ran `runWorker({voters:
    [rulesVoter]})` (the same `voterSet: 'rules_only'` path
    `POST /api/admin/jobs` already exposes, per `routes/admin.js`) against two
    hand-inserted photos. Confirmed (a) a clean roaster+origin mention lands
    in `review_items` with reason `below_threshold` and clean candidate values
    (`"Kolibri"`, `"Ethiopia"`) — the actual vocabulary-confirmation UX #25
    asks for; (b) a `Finca …` mention correctly seeds `origin_farm_id` as
    `no_candidates` (farm vocab is empty, as expected, not a bug); (c) after
    the price/rating fix, a caption with a date and an altitude range but no
    real price/rating proposes neither, while one with a real `"lei"`/`"/5"`
    marker still resolves correctly alongside those same unrelated digits.
  - **Not run against production.** `/api/admin/jobs` on the live Railway
    backend shows zero jobs and `GET /api/coffees` shows `total: 0` — the
    worker has never run against the 28 real photos #20 uploaded, so this
    genuinely would be the first-ever Phase 0 pass over real data once it
    ships. It hasn't shipped: **this branch (`claude/peaceful-mccarthy-kix48i`)
    is not `main`**, same structural issue this file's own 2026-08-01
    correction above describes for `rwi2ql` — the outer harness restricts
    this session's `git push` to its own assigned branch, so `main`
    (`origin/main` at `0ad0023`, dated 2026-07-29) does not move until an
    authorized session merges this branch in. Until that happens, **`#25`
    stays `claimed`, not `done`, in `BACKLOG.md`** (`status/README.md`: "done
    means on the shared branch") and `#26` stays `blocked` — running the real
    5-photo LLM sample (#26) needs this code live on Railway first, and no
    LLM spend happens in this session regardless (Radu's spend gate: rules is
    free, the 5-photo sample needs his go-ahead after seeing #25 confirmed on
    real data, which requires the merge first). — branch
    `claude/peaceful-mccarthy-kix48i`, HEAD after this work.

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

- [2026-08-02 e2a669f] #20 — **`ops/mycoffee_export.py`** + `ops/test_mycoffee_export.py`
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
