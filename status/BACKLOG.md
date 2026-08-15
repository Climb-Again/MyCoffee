# Backlog — the work list the lane routines read

**This file, not the GitHub issue list, is what a scheduled lane session reads.**
Routine-fired sessions run without MCP connector tools, so they cannot query the
GitHub API. Everything a lane needs to choose its next task must be here.

Each row mirrors a GitHub issue of the same number — the issue holds the full
spec, this table holds the scheduling metadata. Full design detail is in `PLAN.md`.

**Status values:** `ready` · `blocked` · `claimed` · `done` · `human`
A lane may only pick a row whose status is `ready`, whose lane matches its own,
and **all of whose `needs` are `done`**. Lowest phase first, then lowest number.
After claiming, set the row to `claimed`; after finishing, `done`.

| # | Lane | Phase | Status | Needs | Item |
|---|---|---|---|---|---|
| 9  | publish   | 0 | done    | — | Real 1024² AppIcon — landed on `main` in `c427f3f` (verified 1024×1024, RGB, no alpha) |
| 10 | publish   | 0 | done    | — | **First TestFlight upload GREEN** (run #15, sha `1336a4b` = current `main`). Autopilot fixed legacy-profile-dir + team-from-profile + `CFBundleExecutable`. Processing (~20 min) → check ASC/email |
| 11 | backend   | 0 | done    | — | Migrations 003, 004, 006 — extensions, vocab tables, FX table |
| 12 | data      | 0 | done    | 11 | Migration 005 — vocab seed (42 countries/89 roasters/148 aliases). Consolidated to `main`, Postgres-validated |
| 13 | data      | 0 | done    | — | `src/lib/normalize.js` + `fuzzy.js` + tests — consolidated to `main`, all green |
| 14 | data      | 0 | done    | 11, 13, 34 | `src/lib/vocab.js` — resolution (exact alias + fuzzy fallback) against `004_vocab.sql`, `origin_country_ids` referential-integrity + multi-value origin split, city→country lookup, DB loaders. 24 new tests, 86/86 green |
| 15 | backend   | 0 | done    | — | Gate the Railway deploy on backend tests |
| 16 | backend   | 0 | done    | — | Fix read auth (`requireAnyToken`) + `GET /api/config` |
| 17 | ios-shell | 0 | done    | — | Models, `CoffeeIndex`, filters/facets/bands, sample repo — **merged to `main`, compile-green** (run #18, `29c1def`) |
| 18 | ios-ux    | 0 | done    | 17 | Design system + listing + filter sheet + sort + detail — **merged to `main`, compile-green** (run #18) |
| 19 | backend   | 1 | done    | 11 | Migration 007 + images/media libs + `routes/photos.js` |
| 20 | data      | 1 | done    | 19 | `ops/` Mac exporter + uploader (osxphotos + sips) — unit-tested (29/29) **AND the on-Mac §8 gate PASSED 2026-08-04**: Radu ran it on the real "coffees" album, 28 photos uploaded, dedupe-on-rerun verified (`0 need an image upload`). Backfill continues as iCloud originals finish downloading |
| 21 | backend   | 2 | done    | 11, 14 | Migrations 008–009 + snapshot + `routes/coffees.js` — verified end-to-end against a local Postgres (insert → generated columns → `GET /api/snapshot`/`/api/coffees/:id`/`top-filters`/favorite all 200 with real data) |
| 22 | ios-shell | 2 | done    | 21 | Remote repository + SyncEngine + ImageStore + MutationOutbox — `RemoteCoffeeRepository` is `CoffeeStore`'s default; found and fixed two real wire-format bugs (`Country`'s `iso2`/`kind` columns, `NUMERIC` columns arriving as JSON strings). See `status/ios-shell.md` for detail + two flagged follow-ups (UX view-wiring for the heart tap / detail-fetch / `ImageStore`; a backend batch-media-URL endpoint for bulk thumbnail prefetch) |
| 23 | backend   | 3 | done    | — | Extend `src/vertex.js` — inline `images`, `responseSchema` (+ `responseMimeType`), `thinkingConfig`, `usage`, `finishReason`. Additive — existing `generateContent()` signature unchanged. Unit-tested via new pure `buildRequestBody()`/`parseResponse()` helpers (no network) |
| 24 | backend   | 3 | done    | 21, 23 | Migrations 010–011 + worker + agents + adjudicate + review routes — verified end-to-end against a real local Postgres with fake voters (no live LLM spend); P3 (rules) left as an optional dynamic import for #25 to add |
| 25 | data      | 3 | done    | 20, 24 | Phase-0 rules-only pass ($0) + vocabulary confirmation — `src/lib/deterministic.js` + tests **MERGED to `main` 2026-08-04** (180/180 green). Includes the `parsePrice`/`parseRating` bare-number-fallback fix (see `status/data.md`) |
| 26 | data      | 4 | done    | 25 | **Accuracy gate PASSED — superseded by real use.** 5-photo sample ran 2026-08-04 (job 7, $0.2154); Radu then used the live builds, judged the picks essentially always right ("haven't found a single miss"), and moved to **accept-by-default** (#35) + **daily 50/day text-only batches**. Job 11 (2026-08-13) extracted 50 photos for $2.72 → 51 coffees total; the daily routine (`trig_01JWhQADZK8RqfP8r9ugXen1`, 06:00 UTC, `includeImages:false`, spendCap $8) is chewing through the remaining ~350 uploaded photos. The 5-photo→25-record→ask ladder is spent; the standing rule now is text-only daily batches + the ~$62 full-backfill still asks first. |
| 27 | ios-ux    | 5 | done    | 22, 24 | Review queue — batch cards, photo auto-zoom, mapping rules — see `status/ios-ux.md`. Runs against a local sample fixture; the real `GET /api/review` feed needs a `CoffeeStore`/`APIClient` surface the shell lane hasn't added yet (flagged in both lane files) |
| 28 | ios-ux    | 5 | done    | 22 | Insights (with statistical gates) + roaster and country pages — see `status/ios-ux.md` |
| 29 | data      | 6 | ready   | 26 | Harden the incremental path — `awaiting_text` sweep, admin sync. (The "launchd monthly" part is effectively covered by the CCR daily-extraction routine; the sweep + admin-sync hardening is still worth doing.) |
| 33 | backend   | 0 | done    | — | `vertex:false` — newline in the env var *name*. Fixed `0b38388`; `/api/status` now `vertex:true` |
| 34 | data      | 0 | done    | — | `fx_rates` seed (1510 rows) + `fx.js` — consolidated to `main`, inversion verified vs anchors |
| 30 | ~~human~~ | — | dropped | — | ~~Set the Actions spending limit~~ **OBSOLETE** — repo is public, Actions free (CLAUDE.md §10). Nothing owed. |
| 35 | backend   | 4 | done    | — | **Accept-by-default adjudication** (PLAN.md §11) — `adjudicateField` now returns `absent` (no candidates, no review row), `accepted` (single/agreeing cluster, applied regardless of confidence), or `split` (>=2 materially-different weighted clusters, review item created but the top-weighted pick is still applied provisionally). See `status/backend.md` for the live before/after `GET /api/review` count from `POST /api/admin/adjudicate`. `src/lib/adjudicate.js`, `worker.js`, `config.js` |
| 36 | backend   | 4 | done    | — | **Human accept creates vocab** (PLAN.md §11) — `POST /api/review/:id` now get-or-creates a `roasters`/`farms` row (+ alias) when a human accepts a name `canonicalize()` can't resolve, instead of 422ing. Countries unaffected (still closed). Done inline in `routes/review.js` (Backend-owned), no `vocab.js` change needed. Verified end-to-end against a real local Postgres (not production — this would mean resolving a real open review item with fabricated test data): an unresolvable farm accept created the row + alias, applied `origin_farm_id`, and closed the review; a second identical accept resolved via the new alias with no duplicate; same for a new roaster. |
| 37 | ios-ux    | 5 | done    | 35, 36 | **"Needs review" reflects only actionable items** (PLAN.md §11) — the detail-page Review button and the Review tab badge both gated on the coarse `Coffee.reviewState` column, which lights up for any open item including the `desc_*` splits `GET /api/review` already excludes server-side. New `Features/Review/ReviewFeedCache.swift` cross-references the real feed (the same one `ReviewQueueView`/`CoffeeReviewSheet` already fetch) and gates both the button and the badge on it; fails open (doesn't suppress) until a fetch actually succeeds, so sample/demo runs with no backend are unaffected. See `status/ios-ux.md` for full detail. |
| 38 | data      | 4 | done   | — | **Roaster countries** — `backend/migrations/014_roaster_countries.sql` populates `roasters.country_id` for 80/89 seeded roasters + backfills `coffees.roaster_country_id`. **Correction to this row's own premise**: the product brief has no roaster↔country pairing at all (verified against `word/document.xml`); sourced via live web search per roaster instead, one at a time, not from the brief. The row's own example "Concept Coffee Roasters→Romania" was wrong (actually Slovakia) — caught by verifying rather than trusting the note. 9 roasters left `NULL` on purpose (ambiguous/no confident source, incl. `Typika` which is genuinely dual Czech Republic+Poland) per Radu's "guess only very close matches" rule. 6 new countries added (Italy, Austria, Sweden, Finland, Slovenia, South Korea). Verified end-to-end against a real local Postgres 16, `npm test` 202/202. See `status/data.md` for the full roaster→country table and the negative/idempotency checks. Deploys via Railway on push; no TestFlight publish needed |
| 40 | backend   | 5 | done   | 36 | **Generic per-field edit endpoint** (PLAN.md §12) — `POST /api/coffees/:publicId/edit` `{field, value}` (+ `{edits:[...]}` batch) landed in `routes/coffees.js`; canonicalize + get-or-create + locked/`decided_by='human'` resolution + apply + close open review items, for ANY field on ANY coffee. Added the missing `roaster_country_id` canonicalize/denormalize/column-update case (`adjudicate.js`/`worker.js`), plus a real latent dedup bug it surfaced (`buildCoffeeColumnUpdates` could double-SET a column across two resolved fields — fixed). Resolve logic shared with `routes/review.js` via new `src/lib/resolveField.js`. Countries stay closed (422 on unknown). Verified end-to-end against a real local Postgres — see `status/backend.md` |
| 41 | ios-shell | 5 | done   | 40 | **Edit API surface** (PLAN.md §12) — `APIClient.editCoffeeField(publicId:field:value:)`; `CoffeeRepository.editField` via the mutation outbox + detail re-fetch; `CoffeeStore.editField`. Dropdown vocab already on-client (`index.vocabulary` + `Profile` enum) — no new read endpoint. Landed on `ios-staging`, see `status/ios-shell.md` for detail (not locally compiled — no Xcode in this sandbox) |
| 42 | ios-ux    | 5 | done   | 40, 41 | **Edit sheet with consistency dropdowns** (PLAN.md §12) — `Features/Coffees/CoffeeEditSheet.swift`, a pencil button on `CoffeeDetailView`'s toolbar opening a `Form` sheet: origin country (multi-select, closed vocab) / roaster country (closed) / roaster / farm (both with an "Add new…" text fallback routing through #40's get-or-create) as searchable pickers over canonical vocab; process as a 5-case + Unknown `Picker` with a separate decaf `Toggle`; altitude/weight/price/rating/roasted-on as bounded inputs, each gated so an untouched optional field never spuriously round-trips. Save diffs against the values the sheet opened with and fires one `CoffeeStore.editField` call (#41) per actually-changed field — see `status/ios-ux.md` for the raw-value formatting per field (e.g. `"250g"`, `"4.5/5"`, `"1800-2000 m"`). The flagged batch-edit gap is closed too: ios-shell added `CoffeeStore.editFields(coffeeId:edits:)` and ios-ux's `CoffeeEditSheet` now calls it whenever a save changes >1 field. |
| 45 | backend   | 6 | done   | — | **`GET /api/whatsnew` + curated content** (PLAN.md §13). Returns `{live:[…], plan:{byLane:{backend,data,ios}, needsApproval:[…]}}` from a committed `backend/src/data/whatsnew.json` (curated prose, kept in sync with this backlog when rows flip). Seeded with current reality (post-#43/#44) — see `status/backend.md` |
| 46 | ios-shell | 6 | done  | 45 | **`whatsNew()` API surface** (PLAN.md §13) — `APIClient.whatsNew()` + lenient-decode `API/Wire/WhatsNewWire.swift` DTOs (`FailableDecodable` on every array, same guard the snapshot/review feeds use). Landed on `ios-staging`, see `status/ios-shell.md` for detail (not locally compiled — no Xcode in this sandbox) |
| 47 | ios-ux    | 6 | done | 45, 46 | **What's New screen** (PLAN.md §13) — `Features/WhatsNew/WhatsNewView.swift`, reached from a new row in `SettingsSheet`. Segmented Live/Plan (`GET /api/whatsnew` via #46's `APIClient.whatsNew()`); Plan pins "Needs your approval" then a fixed Backend/Data/iOS lane order. Read-only v1, no actions. See `status/ios-ux.md` for detail. |
| 44 | backend   | 4 | done    | — | Auto-create farms during adjudication — a confident `accepted` `origin_farm_id` that doesn't resolve against the (0-seeded) farm vocab now get-or-creates the `farms` row via the same #36 machinery, instead of only firing on a human accept. See `status/backend.md` for the live-verified before/after. `src/lib/adjudicate.js`, `src/lib/worker.js`, `src/lib/resolveField.js` |
| 48 | data      | 4 | done   | — | **Roaster country should trust the caption over the vocab guess.** Radu: "Uncommon" resolved to UK though its bag says "Prăjitorie: Uncommon (Amsterdam, Olanda)" = Netherlands. Root cause is a roaster **name collision** — a real UK "Uncommon Coffee Roasters" AND the Amsterdam one merged into one vocab row that #38 guessed as UK. **(a) DONE 2026-08-13** — `backend/migrations/015_fix_uncommon_roaster_country.sql` corrects roaster 89 (`Uncommon`) `country_id` 41 (UK) → 35 (Netherlands) and force-refreshes the 2 affected coffees' denormalized `roaster_country_id` (`IS DISTINCT FROM` for idempotency), bumping `updated_at` so the iOS delta sync ships the fix. Deployed + live-verified (see `status/data.md`). There was only one `Uncommon` DB row — the collision was in the vocab *guess*, not duplicate rows — so a correction, not a split. **(b) DONE 2026-08-15** — `extractRoasterCountryOverride(rawText, countryVocab)` in `src/lib/deterministic.js` (reuses `findAliasMentions`'s diacritic-folded, word-boundary scan already built for the roaster/origin voter fields, filtered to `is_roaster` countries; declines — returns `null` — on zero or on >1 distinct roaster-country mention, same "ambiguous never auto-resolves" rule as city resolution). `backend/migrations/020_add_romanian_roaster_country_aliases.sql` seeds the Romanian country names (`Olanda`, `Cehia`, `Franța`, `Marea Britanie`, …) Radu's own captions actually use — without them the override could never recognise the exact "Olanda" case that motivated this row. 7 new table-driven tests incl. the real Uncommon caption, a diacritic-free spelling, an origin-only mention correctly ignored, and the two-distinct-countries ambiguous case (245/245 `npm test` green). Verified live against a real local Postgres 16 with the actual migration chain applied: `extractRoasterCountryOverride('Prăjitorie: Uncommon (Amsterdam, Olanda)', ...)` resolves to Netherlands (id 35), not UK (id 41). **Wiring into `worker.js` is `backend`-owned — filed as #51**, same split as #39→#49; until #51 lands, the edit sheet (#42) still covers this per-coffee. |
| 43 | backend   | 5 | done    | — | Optimize served photos so caching stays under budget — `display` shrunk 1290px/q82 → 1080px/q72 (~57% smaller on a worst-case noisy test image; real photos should compress even better), plus `POST /api/admin/rederive-photos` to re-derive already-uploaded photos' `display`/`thumb` from their retained `ocr` asset (the raw upload itself isn't kept). See `status/backend.md` for the live-verified before/after. `src/lib/imageDerivatives.js` (new, factored out of `routes/photos.js`), `routes/admin.js` |
| 39 | data      | 4 | done    | — | **Accept-by-default needs field sanity envelopes** (PLAN.md §11 addendum) — `src/lib/normalize.js` `parseAltitude`/`parseWeight`/`parseRating` now hard-reject (`return null` → field reads as absent) instead of only soft-flagging: altitude outside 200–4000m, weight outside 1–5000g, rating outside 0–5. 229/229 `npm test` green. Re-adjudicated all 51 production photos (`POST /api/admin/adjudicate`) — confirmed both live bogus altitudes (2–30m, 1–5m — the exact case Radu flagged) now decide `absent` at the resolution layer (no candidates survive `canonicalize`, no review row opened). **But the visible API still shows the old 2–30/1–5 values** — found and diagnosed a separate, backend-owned gap doing this validation, see new row **#49**. See `status/data.md` for the full writeup. |
| 49 | backend   | 4 | done   | — | **Re-adjudication that flips a field to `absent` doesn't retract an already-materialized `coffees` column** — FIXED: `buildCoffeeColumnUpdates` (`src/lib/worker.js`) now distinguishes "field absent from `resolutions` entirely" (already correctly left alone — `adjudicateRecord` only ever emits a key for a field it actually voted on) from "field present with `decision: 'absent'`" (`value: null`), and explicitly `SET`s the corresponding column(s) to `NULL` for the latter instead of skipping. Applies to every field the function maps, not just altitude (weight, rating, price's 5 columns, roaster_id + its derived roaster_country_id, origin_country_ids + is_blend, profile's 3 columns, origin_farm_id, roasted_on, the 3 desc_* prose columns). 10 new `worker.test.js` cases (236/236 green) plus a live-Postgres reproduction of the exact bug (seeded a coffee with a stale `altitude_min_m/max_m = 2/30`, fed it an implausible `field_candidates` row, ran `adjudicateAndApply` — before the fix the columns stayed `2`/`30`; after, both go `NULL`). See `status/backend.md` for the live production before/after on the two coffee ids #39's own note names. — found while validating #39 in production. `adjudicateRecord` (`src/lib/adjudicate.js`) correctly puts `{value: null, decision: 'absent'}` into the `resolutions` map for a field whose candidates all now fail `canonicalize()` (no `field_candidates` survive → filtered out). But `buildCoffeeColumnUpdates` (`src/lib/worker.js:90`, `if (res.value == null) continue`) treats that identically to "this field was never voted on this pass" and skips it — the stale column from a *prior* accepted decision is never cleared. Live proof: coffees `ZqjVWBODPm-oKNqoCTmQWg` (altitude `2`–`30` m) and `zh8V1tWHHFmq0vyTox1sKQ` (altitude `1`–`5` m, Radu's own example) still show the bogus range via `GET /api/coffees/:id` after #39 shipped and a full `POST /api/admin/adjudicate` re-run — confirmed via `GET /api/review` that neither has an open altitude item (matches "absent → no review row"), so the resolution layer is right and only the denormalized column is stale. Fix needs to distinguish "field absent from `resolutions` entirely" (leave column alone — never voted on, e.g. this photo's caption never mentioned weight) from "field present in `resolutions` with `decision: 'absent'`" (the column must be explicitly `SET … = NULL`) — `buildCoffeeColumnUpdates`/`applyResolutionsToCoffee` is the right layer. Backend-owned (`src/lib/worker.js`), not data lane's to fix. $0 — no LLM spend, just code + a re-run of `POST /api/admin/adjudicate` once shipped, then re-check these two coffee ids. |

| 50 | ios-ux    | 6 | done   | 46 | **Insights charts: per-label average rating + tap-to-filter** (Radu, 2026-08-14) — DONE. Built on `ios-staging` (`348b8cc`) against the pre-#52 single-list Insights layout; reconciled into the #52 3-tab redesign on integration (see the 2026-08-15 ios-ux session note). `PieSlice` carries `key: FacetKey?` (`nil` for "Other") and `averageRating: Double?`; the legend renders `Label · N · ★X.X` and, for any slice with a real key, wraps it in a `Button` that builds a fresh `CoffeeFilter` via the existing `toggleFacet` helper, assigns it to `store.filter`, and sets `store.selectedTab = .coffees` (the seam ios-shell added 2026-08-14). Added the one missing `toggleFacet`/`isFacetSelected` case, `(.decaf, .bool)` — dead code before this (the filter sheet special-cases decaf as a segmented control, never routes it through the generic pill toggle), needed because `.decaf` is one of Insights' pie dimensions. `RootTabView`'s `TabView` now binds `selection: $store.selectedTab` with a `.tag(RootTab.*)` per tab. See `status/ios-ux.md` for full detail. |

| 51 | backend   | 4 | done    | — | **Wire #48(b)'s caption-city roaster-country override into `worker.js`.** DONE — `extractRoasterCountryOverride` is now called from `buildCoffeeColumnUpdates`'s `roaster_id` case, preferring its result over the vocab-derived country and falling back when it returns `null`; `adjudicateAndApply` threads `rawText` into the ctx. Live-verified against a real local Postgres (a caption-stated country beat a differing vocab-derived one; no-caption-mention fell back correctly). Deployed to `main`, Railway redeploy green. **Not yet re-applied to already-adjudicated production rows** — the session's own permission classifier denied the live `POST /api/admin/adjudicate` re-run, so stale `roaster_country_id` values a caption-override would correct are still whatever the vocab-derived value was; a future session (or Radu) can run it retroactively, $0/no LLM spend, or it'll apply automatically on the next fresh extraction pass. See `status/backend.md` for full detail. `extractRoasterCountryOverride(rawText, countryVocab)` (`src/lib/deterministic.js`, data-owned, 7 table-driven tests, live-Postgres-verified) is ready to call — it returns a country id when the caption unambiguously states the roaster's own city/country (e.g. "Prăjitorie: Uncommon (Amsterdam, Olanda)" → Netherlands), or `null` when the caption says nothing / is ambiguous, in which case the existing vocab-derived country should still apply. Two changes needed in `buildCoffeeColumnUpdates`'s `roaster_id` case (currently unconditionally `set('roaster_country_id', roaster?.country_id ?? null)`): (1) thread `rawText` into the `ctx` object — today `applyResolutionsToCoffee`'s ctx is `{...sharedCtx, photoDate}`, no `rawText`, even though `adjudicateAndApply` already has it in scope; (2) call the override and prefer its result, falling back to `roaster?.country_id` when it returns `null`. Takes effect the next time `POST /api/admin/adjudicate` re-runs — $0, no LLM spend, re-derives from stored `field_candidates`. `backend/migrations/020_add_romanian_roaster_country_aliases.sql` already seeds the Romanian country names (Olanda, Cehia, Franța, Marea Britanie, SUA, …) the override needs to recognise Radu's own caption language — nothing further needed there. `src/lib/worker.js`, `test/worker.test.js`. |

| 52 | ios-ux    | 6 | done    | 46 | **Insights redesign — 3 sub-tabs + chart time windows + average rating everywhere** (Radu, 2026-08-15). DONE in `85d6911` (compile-green run #60; published to TestFlight same session). `Features/Insights/{InsightsView,InsightsCharts}.swift`. (1) Segmented sub-tabs **Insights / Charts / Data**: Insights = new headline card (coffee count + overall ★ average) + the "This month" brief + the "what tends to score well" findings; Charts = the per-dimension pie breakdowns; Data = the data-quality card. (2) Charts get a time-window control **All / last 12m / last 18m / By year** — the month windows are relative to today (`Calendar.utc`, `purchasedOn.utcMidnight`), "By year" drops multi-select year chips newest-first (reuses `FilterPill`, each shows its count). Windowed breakdowns are computed by building a throwaway `CoffeeIndex` over the date-filtered subset and calling the same `facets(for:)` the listing uses, so the pies + averages match what filtering to that window would show. (3) **Average rating surfaced everywhere** — every pie legend slice reads `Label · 12 · ★4.3` (the "Other" bucket carries no average — per-entry means can't be re-averaged without rated counts), the Insights headline shows the overall average, the Charts summary shows the window's average. (4) **Removed the standalone "Average rating by year" chart** (`RatingByYearChart` deleted) — the Year-bought pie's legend now carries per-year averages, so the data lives there. **This was built directly on `origin/main`, bypassing `ios-staging`, and had to be reconciled with #50's independently-built tap-to-filter work on integration** — see the 2026-08-15 ios-ux session note in `status/ios-ux.md`. |

| 53 | ios-ux    | 6 | done    | 46 | **Insights findings: link the key phrase to the filtered listing** (Radu, 2026-08-15) — DONE. `InsightsFinding` gained `subjectText: String?` (the exact phrase to link, e.g. "Panama-origin coffees") and `subject: FindingSubject?` (a `dimension`+`FacetKey` pair) — populated for every categorical finding (profile, decaf, origin country, roaster country, roaster), left `nil` for ordinal findings (altitude/price/year), which have no single filterable value. The view renders each finding via an `AttributedString` with the subject phrase carrying a `.link` attribute (a synthetic `mycoffee-finding://<uuid>` URL) — only that span is tappable, not the whole sentence — intercepted by an `.environment(\.openURL, OpenURLAction { ... })` on `findingsSection` that looks the finding up by id and calls the same `selectInCoffees(dimension:key:)` the Charts tab's legends (#50) already use. `Features/Insights/{InsightsView,InsightsFindings}.swift`. |
| 54 | ios-ux    | 6 | done    | 46 | **Data-quality card items deep-link to the filtered listing** (Radu, 2026-08-15) — DONE. `InsightsAggregation.DataQualityField` gained a `dimension: FilterDimension?` — set for every field with a real Unknown facet (Rating→`.ratingBand`, Process→`.profile`, Origin country→`.originCountry`, Roaster country→`.roasterCountry`, Altitude→`.altitudeBand`, Price→`.priceBand`), left `nil` for Weight (not a listing facet at all, per the row's own caveat). `DataQualityCard` wraps a row in a `Button` only when its field has a dimension; tapping calls a new `InsightsView.selectUnknownInCoffees(dimension:)` that builds a fresh `CoffeeFilter` with just that dimension's Unknown bucket selected and switches to the Coffees tab. `Features/Insights/{DataQualityCard,InsightsAggregation,InsightsView}.swift`. |

| 55 | ios-ux    | 6 | done    | — | **Review source-photo zoom is dead — make it a real full-screen zoom** (Radu, 2026-08-15) — DONE. New `DesignSystem/ZoomableImageView.swift`: a shared full-screen pan+zoom surface (pinch to scale via `MagnificationGesture`, double-tap to zoom in/out, drag-to-pan gated on `scale > 1` via a `SimultaneousGesture(pinch, drag)`, bounded 1×–5×, black background, a real `Button` close ✕) presented with `.fullScreenCover`. `ReviewCardView.swift`'s `ReviewPhoto` now opens it on tap of the photo *or* the zoom icon (both call the same `showFullScreen = true`, the icon is now a real `Button` instead of a decorative overlay) instead of the broken in-card `scaleEffect`/`MagnificationGesture` combo that the enclosing scroll view's drag recognizer swallowed. Also swapped `CoffeeDetailView.swift`'s near-identical private `FullPhotoView` for the same shared component and deleted the now-dead duplicate, closing the row's own "would benefit from the same viewer" note for the coffee detail hero photo too. `Features/Review/ReviewCardView.swift`, `Features/Coffees/CoffeeDetailView.swift`, `DesignSystem/ZoomableImageView.swift`. |

| 56 | backend   | 6 | done    | — | **Listing search doesn't hit full text — the search blobs are never populated** (Radu, 2026-08-15). DONE — `buildSearchBlobs(coffee, ctx)` (pure, `src/lib/worker.js`) derives both blobs from resolved vocab names (roaster, roaster country, every origin country, farm, profile name + `profile_detail`) and prose (`raw_title`+`raw_caption`+`raw_description`), diacritic-folded via `foldDiacritics`. `refreshSearchBlobs()` re-reads the coffee row post-update and writes both columns; wired into `applyResolutionsToCoffee` (shared by the adjudication path AND `routes/coffees.js`'s generic edit endpoint, so both write paths in the row's own ask are covered by one call site). One-time backfill: `POST /api/admin/rebuild-search-blobs` (ingest-token-gated, `rebuildAllSearchBlobs()`) recomputes both columns for every existing coffee — scoped to just the two blob columns, not a full re-adjudication. 8 new `worker.test.js` cases (252/252 green). Live-verified against a real local Postgres 16 (fresh DB, migrations 001→020 applied clean): a coffee resolved via `applyResolutionsToCoffee` got non-empty, correctly-folded blobs and a working `search_tsv` (labels weighted `A`, prose `D`); a second coffee seeded with empty blobs (simulating a pre-existing production row) got both populated by `rebuildAllSearchBlobs()`. **Confirmed the bug live pre-fix**: `GET /api/snapshot/text` on production returned 120 coffees, 0 non-empty blobs — matches the row's own claim exactly. See `status/backend.md` for the full write-up and the post-deploy backfill result. `src/lib/worker.js`, `src/routes/admin.js`, `test/worker.test.js`. |

| 57 | ios-ux    | 6 | ready   | — | **Add a "rotate photo" option in the photo viewer** (Radu, 2026-08-15). Some source photos come in sideways; give the user a way to rotate them 90° for viewing. Add a rotate control to the photo viewer(s) — the coffee-detail photo (`Features/Coffees/CoffeeDetailView.swift`) and, once #55 lands, the shared full-screen zoomable viewer (best home for it; pairs with pinch/pan). **Scope question for Radu — surface before building:** is view-only rotation enough (rotate resets when you leave the screen — pure client, no backend), or must the corrected orientation **persist** across launches/devices? Persisting means either storing a per-photo rotation on the coffee/asset (backend column + `/edit`-style endpoint + snapshot field, a cross-lane change) or re-encoding the stored derivatives server-side (`routes/admin.js` rederive path) — a materially bigger job. Default to **view-only** unless Radu asks for persistence. `Features/Coffees/CoffeeDetailView.swift` (+ the #55 viewer); persistence variant also pulls in backend + shell. |
| 58 | ios-ux    | 6 | ready   | — | **Move the listing search box to the bottom (iOS 26 style)** (Radu, 2026-08-15). The Coffees-tab search is `.searchable(text: $store.filter.query, prompt:…)` at `Features/Coffees/CoffeesListView.swift:50`, which docks in the nav bar up top. iOS 26 anchors search at the bottom (thumb-reach); adopt that placement — e.g. the iOS 26 bottom/tab-bar search treatment (`.searchable` bottom placement / `searchToolbarBehavior`, or a bottom search accessory on the tab), matching the system pattern rather than a custom bar. Build targets the iOS 26 SDK (Xcode 26) so the API is available. Keep the same binding + prompt; this is placement only — behaviour and the `filter.query` wiring don't change. Verify it doesn't collide with the sticky section headers already on this list. `Features/Coffees/CoffeesListView.swift` (possibly `Features/Root/RootTabView.swift` if the iOS 26 pattern hangs search off the tab view). |
| —  | —         | — | dup     | — | **"search in all text"** (Radu, 2026-08-15) — same as **#56** (listing search doesn't hit full text because the backend search blobs are never populated). Tracked there; no separate row. |

| 56 | backend   | 6 | ready   | — | **Listing search doesn't hit full text — the search blobs are never populated** (Radu, 2026-08-15). Searching the Coffees listing matches labels (roaster/origin/etc.) but not the coffee's full prose text. Root cause is a backend gap, not iOS: migration `009_search.sql` adds `search_labels_blob` / `search_prose_blob` (+ a generated `search_tsv` GIN index), and `GET /api/snapshot/text` (`routes/coffees.js:134`) serves `[labels_blob, prose_blob].join`, which iOS already folds into `CoffeeIndex.searchKeys` (`SyncEngine.snapshotText()` → `searchTexts`). **But no backend code ever WRITES those two columns** — grep shows they're only ever read; they stay at their `''` default. Verified live 2026-08-15: `GET /api/snapshot/text` returns 120 coffees, **0 non-empty blobs**. Fix (backend-owned): populate both blobs on every coffee write — `search_labels_blob` from the resolved label names (roaster, roaster country, origin countries, farm, profile display), `search_prose_blob` from the prose (`raw_title` + `raw_caption` + `raw_description`, and any appended OCR text), **diacritic-folded in JS** (`foldDiacritics`, the migration comment says the blobs are pre-folded so `to_tsvector('simple')` needs no unaccent). Wire it into `buildCoffeeColumnUpdates`/the upsert in `src/lib/worker.js` (adjudication path) **and** the per-field edit path in `routes/coffees.js` (so an edited roaster/prose updates the blob). Add a one-time backfill for the existing 120 coffees (admin endpoint or migration that recomputes from current `raw_*` + resolved vocab). No iOS change needed — the client already consumes the endpoint; blobs just need to stop being empty. `src/lib/worker.js`, `src/routes/coffees.js`, a backfill, `test/worker.test.js`. |

**Unblocking is a normal part of the job.** When you finish an item, flip every row
whose `needs` are now all `done` from `blocked` to `ready` in the same commit. If
you don't, the next lane has nothing to pick up.

## Right now

**🌱 2026-08-15 (data lane) — #48(b) is DONE; filed #51 (backend) for the wiring.**
`extractRoasterCountryOverride(rawText, countryVocab)` lands in
`src/lib/deterministic.js`, reusing the same `findAliasMentions` primitive
`extractOriginCountriesField` already uses (diacritic-folded, word-boundary
scan), filtered to `is_roaster` countries and declining (returns `null`) on
zero or on >1 distinct roaster-country mention. `backend/migrations/
020_add_romanian_roaster_country_aliases.sql` seeds the Romanian country
names (`Olanda`, `Cehia`, `Franța`, `Marea Britanie`, `SUA`, …) actually used
in Radu's own captions — without them the override could never recognise the
exact "Olanda" spelling that motivated this row in the first place. 7 new
table-driven tests (245/245 `npm test` green) including the real Uncommon
caption, a diacritic-free spelling, an origin-only mention correctly ignored,
and the ambiguous two-distinct-countries case. Verified live against a real
local Postgres 16 with the full migration chain (001→020) applied:
`extractRoasterCountryOverride('Prăjitorie: Uncommon (Amsterdam, Olanda)',
countryVocab)` resolves to Netherlands (id 35), confirming the override would
have produced the right answer #38 originally got wrong. **This function
isn't wired into the live pipeline yet** — that's `worker.js`
(`buildCoffeeColumnUpdates`'s `roaster_id` case), which is backend-owned, not
data lane's to edit — filed as **#51 (backend, ready)**, same split as
#39→#49. No other `data` row was `ready` at a lower phase (#29 is phase 6,
needs 26 which is done, stays `ready` for a future data session).

**🌱 2026-08-14 (data lane) — #39 is DONE; found and flagged a backend gap while validating it in production, new row #49.**
`normalize.js`'s `parseAltitude`/`parseWeight`/`parseRating` now hard-reject
implausible values to `null` instead of only soft-flagging (229/229 tests green).
Landed on `main`, Railway redeployed, then ran the $0 validation PLAN.md §11
addendum calls for: `POST /api/admin/adjudicate` re-adjudicated all 51
production photos. The resolution layer is provably correct — both live bogus
altitudes (including Radu's own `1–5 m` example) now decide `absent`, and
neither opened an altitude review item. **But `GET /api/coffees/:id` still shows
the old bogus values** — `buildCoffeeColumnUpdates` (`worker.js`, backend-owned)
skips a field whenever its resolved `value` is `null`, whether that's because it
was never voted on or because it just flipped from a stale `accepted` decision to
`absent` — so a previously-materialized column is never retracted. Documented in
full in row **#49** (backend, ready) and `status/data.md`; not something data
lane can fix (`worker.js` is outside `ops/**`/`src/lib/{normalize,fuzzy,vocab,fx,
deterministic,prompts}.js`). No other data row was `ready` at this phase besides
#48(b), which stays open for a later session — lowest-number rule picked #39 first.

**📱 2026-08-12 (ios-shell lane, later session) — #46 is DONE.** `APIClient.whatsNew()`
+ lenient-decode `WhatsNewWire.swift` DTOs land on `ios-staging`. Also reconciled a
`status/BACKLOG.md` merge divergence on the way in — `ios-staging` didn't yet know
`main` had `#45` done/`#46` ready, `main` didn't yet know `ios-staging` had `#41`/`#42`
done — see `status/ios-shell.md` for the full reconciliation. **`#47` (ios-ux) flipped
`blocked`→`ready`** in the same push — its other need, `#45`, was already done on `main`.

**🛠️ 2026-08-12 (backend lane, later same day) — #45 is DONE.** `GET
/api/whatsnew` (PLAN.md §13) ships from a new committed
`backend/src/data/whatsnew.json`, `requireAnyToken`-gated. Content reflects
current reality as of this push (post-#43/#44): Live now includes farm
auto-create, roaster countries, accept-by-default, the shrunk photo cache and
the generic edit API; Plan/byLane lists #37/#39/#41/#42/#48 plus this row's
own #46/#47 follow-ups; needsApproval lists the pending iOS TestFlight batch,
the ~$62 backfill, and the 50 MB cap. Full detail in `status/backend.md`.
**`#46` (ios-shell) flipped `blocked`→`ready`** in the same push; `#47`
(ios-ux) stays `blocked` — it also needs `#46`.

**✅ 2026-08-12 (ios-ux lane) — the batch-edit call-site swap below is DONE.**
`Features/Coffees/CoffeeEditSheet.swift`'s `save()` now sends one
`CoffeeStore.editFields(coffeeId:edits:)` call when a save changed more than
one field, instead of looping `editField` per field — closes the atomicity
gap the ios-shell entry just below flagged, same session cycle. Single-field
saves still use `editField` unchanged. See `status/ios-ux.md` for detail; not
locally compiled (no Xcode here), but this is a narrow call-site change
against an already-public type (`CoffeeFieldEdit`), so a red compile check
would most likely be a typo, not a design gap.

**🔗 2026-08-12 (ios-shell lane) — closed #42's flagged batch-edit atomicity
gap, no new backlog row.** No `ios-shell` row was actually `ready` this cycle
(`#41` below was already `done` on `ios-staging` — `main`'s copy of this file
just hadn't caught up yet, dev/ship split as usual). Instead closed the gap
`status/ios-ux.md`'s `#42` write-up flagged and explicitly asked shell to pick
up: `CoffeeEditSheet` fires one `editField` HTTP request per changed field,
so a same-save `roaster` + `roasterCountry` edit has no ordering guarantee
against each other even though the backend's batch `{edits:[...]}` endpoint
(#40) exists precisely to avoid that. Added `APIClient.editCoffeeFields`,
`CoffeeStore.editFields(coffeeId:edits:)`, and the matching
`CoffeeRepository`/`MutationOutbox`/`SyncEngine` plumbing — see
`status/ios-shell.md` for full detail. **ios-ux: swap `CoffeeEditSheet`'s
per-field `editField` loop for one `editFields` call when >1 field changed in
the same save** — that's the only remaining step to actually close the gap.

**🛠️ 2026-08-12 (backend lane) — #44 and #43 are DONE.** Batched both, plus a
markdown-table repair — full detail in `status/backend.md`. Short version:
#44 lets a confident new farm name auto-create its `farms` row instead of
sitting inert (farm was 0/21 in the app); #43 shrinks the `display` photo
variant and adds a re-derive pass for photos uploaded before the shrink.
While editing #43's row, found it had been silently corrupted into a single
malformed markdown table row carrying **both** #43's and #39's content (a
stray `|` mid-cell, not a content problem) — split back into two proper rows
so #39 (data, `normalize.js` sanity envelopes) is visible to a row-scan again
instead of being invisible dead text inside #43's cell.

**✏️ 2026-08-11 (ios-ux lane) — #42 is DONE.** Edit sheet with consistency
dropdowns (PLAN.md §12): a pencil button on `CoffeeDetailView`'s toolbar opens
`CoffeeEditSheet` (`Features/Coffees/CoffeeEditSheet.swift`), a `Form` with
searchable pickers over canonical vocab for origin country (multi-select),
roaster country, roaster, and farm (the latter two with an "Add new…" text
fallback into #40's get-or-create — countries stay closed per #36, no
add-new there), a segmented process picker (5 cases + Unknown) with a
separate decaf toggle, and bounded inputs for altitude/weight/price/rating/
roasted-on. `Save` diffs every field against the value the sheet opened with
— not just "is the control non-empty" — so an untouched optional field (e.g.
a coffee with no rating yet, where the slider defaults to a visible 3.0)
never fires a spurious edit; each changed field becomes one
`CoffeeStore.editField` call (#41). Picked up straight from `BACKLOG.md`
without rediscovering #41 first: merging `origin/main` into `ios-staging`
surfaced that `#41` (ios-shell) had already landed there (`5b76a6c`) and
flipped `#42`'s row to `ready`, while `main`'s own copy of the table still
showed `#41` merely `ready`/`#42` `blocked` — same "each branch only knows
its own lane's latest" pattern this file has hit before (see the 2026-08-10
ios-shell entry below). Resolved the merge conflict by keeping `ios-staging`'s
more current rows. Full per-field raw-value formatting + the one flagged
client-side gap are in `status/ios-ux.md`. Not locally compiled (no Xcode
here) — flag the compile lane to `Features/Coffees/CoffeeEditSheet.swift`
first if the next check goes red; the `Profile?`-tagged `Picker` and the
`VocabEntry` `Identifiable` wrapper (added to dodge tuple-keypath ambiguity
in `ForEach`) are the two least-proven-by-precedent pieces in this file.

**📱 2026-08-11 (ios-shell lane) — #41 is DONE.** Edit API surface (PLAN.md
§12): `APIClient.editCoffeeField(publicId:field:value:)` (same raw-string-in
shape as `resolveReview` — checked `resolveField.js`'s `canonicalize()`,
every field runs the raw value through a string parser, no structured shape
to bridge); `MutationOutbox` gets a fourth `PendingMutation` case (`.edit`,
one outstanding edit per `(coffeeId, field)`, falls into the existing
4xx-drops/5xx-retries split); `SyncEngine.editField` queues + flushes like
`setFavorite` then re-fetches detail on success (unlike a favorite bool, an
edit's backend-derived side effects — e.g. `roaster` deriving
`roasterCountryId` — can't be guessed at locally); `CoffeeStore.editField`
merges the refreshed `Coffee` into `index`. `SampleCoffeeRepository`'s is a
no-op, same reasoning as its `resolveReview`/`dismissReview` no-ops. Landed on
`ios-staging`, not `main` (this lane never pushes `ios/**` to `main` — see
`status/ios-shell.md` for full detail). **`#42` (ios-ux) flipped
`blocked`→`ready`** in the same push; it also needed `#40`, already done.
Not locally compiled (no Xcode here) — a red compile check should point at a
typo, not a design gap, since every piece mirrors an existing shape.

**🛠️ 2026-08-11 (backend lane) — #40 is DONE.** Generic per-field edit endpoint
(PLAN.md §12): `POST /api/coffees/:publicId/edit`, single or batch. Reuses
#35/#36's locked-resolution + get-or-create machinery via a new shared
`src/lib/resolveField.js` (also now used by `routes/review.js`, refactored
per the issue's own ask). Added the `roaster_country_id` direct-edit case the
row called out, and fixed a real bug it exposed: batching a `roaster` edit
with a `roasterCountry` edit in the same call used to emit two SET clauses
for the same column (Postgres error) — `buildCoffeeColumnUpdates` now dedupes
by column. Full verification detail (curl-driven, against a real local
Postgres, including the batch-edit-wins-over-derived-value proof) in
`status/backend.md`. **`#41`(ios-shell) flipped `blocked`→`ready`** in the
same push; `#42` (ios-ux) stays `blocked` — it also needs `#41`.

**🌍 2026-08-10 (data lane) — #38 is DONE, and its own premise was wrong.**
The row said to seed `roasters.country_id` "from the product brief" — verified
directly against the docx's `word/document.xml` that it holds no such pairing
at all (just a flat roaster-name list and two flat, already-known-swapped
country tallies). Sourced live via web search per roaster instead of guessing
from names; caught the row's own example ("Concept Coffee Roasters→Romania")
being wrong (it's Slovakia) in the process. 80/89 roasters now have a country;
9 left `NULL` on purpose per Radu's "guess only very close matches" brief line
rather than pattern-matched. Full table + verification in `status/data.md`.
No other `data` row was `ready` this cycle (`#26` still `human`, `#29` still
blocked on it) — nothing else picked up.

**🧭 2026-08-08 (Radu directive) — accept-by-default; review is optional, not a gate.**
After using the live builds Radu was explicit: the extractor's picks are
essentially always right ("69.00 lei in text → 69.00 lei picked = definitely
correct; haven't found a single miss"). He wants to **push identified info and
correct the rare mistakes**, not review everything. New backlog rows **#35–#37**
carry this out; full design is **PLAN.md §11**. #35 (accept-by-default
adjudication) is the headline and is $0 to iterate — re-adjudication runs over
stored `field_candidates`, no new LLM spend — so tune it against the existing
corpus. Two concrete bugs feed the same theme: (a) **reviewing a farm name does
nothing** because 0 farms are seeded and the resolve endpoint 422s (→ #36,
get-or-create on accept); (b) **most "needs review" coffees open an empty review
sheet** because their open items are non-reviewable fields (→ #35 removes those
rows at the source; #37 is the client belt-and-braces).

**📦 2026-08-08 — a batch of UI/review fixes is already on `main`, awaiting the Publish lane.**
Do **not** re-implement these; they're landed (`main` `9bb27d6..2b3b0e1`) and
compile-green, just not yet dispatched `publish=true`:
real review feed wired to `GET/POST /api/review` (backend enrich: signed
`thumbUrl` + raw text + field mapping + candidate cleaning; canonicalizing,
corruption-safe resolve); full source text on the coffee page + review card
(now a collapsible section, expanded by default); listing thumbnails carried in
the snapshot (`SNAPSHOT_VERSION=2`, survives re-sync); per-coffee review sheet
from the "needs review" marker; single back arrow + removed the overlapping
inline thumbnail on the coffee page; review card swipe→buttons + Back (was
dismissing on scroll); **multiple origins shown for blends**; and the
**vertical-wrapped process-tag** fix (`lineLimit(1)` + `fixedSize`). Radu asked
**not to manually publish** — the Publish lane ships `main` on its Thu/Sun cron.

**🔀 2026-08-04 (ios-shell lane, merging `main` into `ios-staging`) — reconciled a
second branch-divergence, same shape as the `#27` one below.** `ios-staging` had
`#22`/`#27`/`#28` (iOS) done but only knew `main`'s older state for `#25`/`#26`
(showed `ready`/`blocked`); `main` had `#25` done and `#26` promoted to `human`
(Radu's 5-photo verdict pending) but only knew `#22` as `ready` and `#27`/`#28` as
`blocked` (ios-staging doesn't push to `main`, so `main` never saw the iOS lane's
work land). The table above now reflects both halves: `22/25/27/28` done, `26`
human. No new code in this reconciliation — same "each branch is stale about the
other's lane" pattern `status/README.md` calls out, not a regression.

**🟢 2026-08-04 (ios-ux lane, later same session) — `#27` is DONE.** Review
queue built in full against a local sample fixture (`ReviewSampleData`):
batch-card collapsing at the ≥8 threshold, per-coffee singles ordered by
fewest-open-fields-first, all five gestures (tap/long-press/swipe
right/left/down), a 20-deep undo stack with a 5 s toast, and an "Other…"
free-text fallback. **One real gap, flagged rather than guessed around** (see
`status/ios-ux.md`): the real `GET /api/review` / `POST /api/review/:id` /
`POST /api/review/rules` feed has no `CoffeeStore`/`APIClient` surface yet —
same class of gap as #28's flagged `loadBrief()` — so every action today only
mutates local state, nothing round-trips through the mutation outbox. Claimed
in both `status/ios-ux.md` and `status/ios-shell.md` per the seam rule in
`status/README.md`.

**🟢 2026-08-04 (ios-ux lane, merging `main` into `ios-staging`) — `#27` flipped `blocked`→`ready`.**
Each branch only knew half the picture: `ios-staging` had `#22` (ios-shell) done
but still carried a stale `blocked` for backend's `#23`/`#24`/`#25`; `main` had
`#23`/`#24` done but still showed `#22` as merely `ready` (ios-shell doesn't push
to `main`, so `main` never saw it land). `#27`'s `needs` are `22, 24` — both are
in fact done once the two branches are reconciled — so this merge is what
surfaces `#27` as this lane's next row, not new work by either lane individually.

**#22 is DONE (2026-08-01, ios-shell session)** — `RemoteCoffeeRepository` +
`SyncEngine` + `MutationOutbox` + `ImageStore` land, delta-syncing
`/api/snapshot` and persisting to disk; `CoffeeStore`'s default repository is
now the real one, not `SampleCoffeeRepository`. Full detail + two real
wire-format bugs found and fixed (`Country`'s `iso2`/`kind` columns vs.
`isoCode`/`isPseudo`; Postgres `NUMERIC` columns arriving as JSON strings, not
bare numbers) in `status/ios-shell.md`. Unblocks **#28** (ios-ux), flipped
`blocked`→`ready` above; **#27** stayed `blocked` at the time (still needed
`#24`, which was only `blocked` on `main` as of this ios-shell session — see
the 2026-08-04 note at the top of this section for the merge that resolved it).

Two follow-ups flagged, not done in this session because they're outside
`ios-shell`'s owned paths or backend-owned:
- **iOS UX**: `DesignSystem/Thumbnail.swift` still uses a plain `AsyncImage`,
  not the new `ImageStore`; and no view calls the new
  `CoffeeStore.toggleFavorite(_:)` / `.loadDetail(for:)` yet — the heart icon
  in `CoffeeRowView.swift` has no tap gesture, and `CoffeeDetailView.swift`
  never fetches the detail payload that carries real notes/images (the
  compact snapshot doesn't). Both store methods exist and are ready to call.
  **Resolved** in the 2026-08-02 ios-ux session below (`Thumbnail.swift` now
  uses `ImageStore`, the heart has a tap target, detail fetches on appear).
- **Backend**: the compact snapshot has no per-row image URL, so bulk
  thumbnail prefetch (PLAN.md §5) has nothing to prefetch from yet — a batch
  media-URL endpoint doesn't exist. `ImageStore` is built and ready once one
  does; not guessing its shape here, same as the backend lane's own note
  below about this exact gap.

**✅ 2026-08-04 (authorized session) — `claude/peaceful-mccarthy-kix48i` is MERGED.**
The stranded #25 work below is now on `main` (clean fast-forward, `npm test`
180/180 re-verified post-merge). `#25`→`done`, `#26`→`ready`. Radu explicitly
authorized the 5-photo LLM sample (spend-gate step 2), so the Phase-0 rules pass
($0) and then the 5-photo sample are being run against the real 28 photos in this
session. The "needs an authorized session to merge" ask below is now SATISFIED —
don't act on it again.

**🟡 2026-08-04 (data lane) — #25's code is done, but not yet on `main`.**
`backend/src/lib/deterministic.js` (the P3 "rules" voter) + tests landed and
were verified end-to-end against a real local Postgres 16 — see
`status/data.md` for the full writeup, including a real bug this pass found
and fixed (`parsePrice`/`parseRating`'s bare-number fallback grabbing an
unrelated digit — a date, an altitude — out of free text when nothing else in
the caption looked like a price or rating). **Left `#25` at `claimed`, not
`done`** — this session's `git push` is restricted to its own branch
(`claude/peaceful-mccarthy-kix48i`), which is not `main` (`origin/main` is
still `0ad0023`, from 2026-07-29, well behind even this file's own account of
what's landed). Per `status/README.md`'s "done means on the shared branch"
rule, `#25` can't be marked `done` and `#26` can't unblock until an authorized
session merges `claude/peaceful-mccarthy-kix48i` into `main` — the same
structural gap `status/data.md`'s 2026-08-01 correction already documented for
`rwi2ql`. **Nothing has been run against production**: the live Railway
backend's `/api/admin/jobs` is empty and `GET /api/coffees` reports
`total: 0` — the worker has genuinely never touched the 28 real photos #20
uploaded, so the actual Phase 0 pass over real data — and any LLM spend under
#26 — waits on this merge. Whoever can push to `main`: fast-forward/merge
`claude/peaceful-mccarthy-kix48i`, confirm `npm test` (180/180) and the
Railway deploy, then flip `#25`'s row to `done` and `#26` to `ready`.

**🟢 2026-08-04 (later same day, backend lane) — #24 is DONE.** Migrations
`010_extractions`/`011_resolutions` + `src/lib/adjudicate.js` (pure
deterministic adjudication) + `src/lib/agents.js` (the 4 LLM voters) +
`src/lib/worker.js` (the SIGTERM-safe claim-with-lease loop) +
`routes/review.js` + `routes/admin.js` all landed on `main`, verified
end-to-end against a real local Postgres using fake no-network voters (no
live Vertex spend -- that stays gated behind the data lane's spend protocol
below). See `status/backend.md` for full detail, including the one deliberate
scope gap (the "provisional pass while still awaiting_text" nuance from
PLAN.md §3 isn't implemented yet -- only `text_received`/deadline-passed
photos are claimed). **`#25` (data) flipped `blocked`→`ready`** — its own gate
(Radu's spend protocol below) still applies before any real LLM run.
P3 (rules) is intentionally absent: `agents.js`'s `loadRulesVoter()` dynamically
imports the data lane's `src/lib/deterministic.js` and simply runs without it
if that file doesn't exist yet, so `#25` can add it without any backend-side
coordination -- the only contract is a `{agent:'rules', provider:'rules',
run(ctx) => Promise<{fields, usage, costUsd}>}` voter object.

**🟢 2026-08-04 — the on-Mac §8 photo gate has RUN AND PASSED (Radu, real Mac).**
The exporter ran against the real "coffees" Photos album: 28 originals uploaded to
`POST /api/photos/manifest` + `PUT /api/photos/:sourceId/image`, and a second run
returned `0 need an image upload` (dedupe verified). This is the gate the backend
lane had been holding `#23`/`#24` on ("blocked on purpose per §8"). **That block is
now lifted: `#23` flipped `blocked`→`ready`.** Backend lane: `#23` (extend
`vertex.js`) is your next row; finishing it unblocks `#24` (worker/agents), which
unblocks `#25` (the first extraction pass — which has its own 5-photo spend gate in
`#26` before any real spend). More photos keep arriving as Radu's iCloud originals
finish downloading and he re-runs the exporter (idempotent).

**#20 is DONE** (2026-08-02, data lane session) — `ops/mycoffee_export.py`, the
two-phase Mac exporter + uploader against `POST /api/photos/manifest` +
`PUT /api/photos/:sourceId/image` (`routes/photos.js`, #19). Structured so the
pure logic (manifest-entry shaping, ≤200-entry batching, an on-disk
`(size, mtime)` state cache that skips re-`sips`-converting unchanged photos,
HTTP retry/backoff that never retries a 4xx) is unit-tested without macOS —
`ops/test_mycoffee_export.py`, 29/29 green — and only the Photos-library read
(`osxphotos`) and HEIC→JPEG conversion (`sips`) are macOS-specific, isolated
behind lazy imports so the test run needs neither installed. Full detail,
including the `contentSha256`-must-equal-the-uploaded-bytes trap and why
`caption` is always sent `null`, is in `ops/README.md`.

**Not done, and can't be from this sandbox:** the actual on-Mac verification
gate PLAN.md §8 asks for — run against Radu's real "Coffees" album with
`--limit 20`, confirm derivatives + dedupe-on-rerun. This session has no
macOS runner and no access to the real Photos library; `ops/README.md` has a
checklist ready for whoever runs it. `#25` (needs 20, 24) stays `blocked` —
`#24` is still blocked upstream, so nothing newly unblocks this session.

**✅ 2026-08-01 (Backend lane session): the `claude/peaceful-mccarthy-rwi2ql`
merge described in the warning below is DONE — this is real `origin/main` now.**
The prior backend session that wrote the warning had validated the branch
(86/86 tests) but had its direct push to `main` blocked by its own session's
permission classifier. This session re-verified the same result, merged it
(`git merge --no-ff` then `git pull --rebase` linearized it onto `main` as
three commits, no conflicts — `main` had only moved by two backend audit-note
commits since), reran the suite (still 86/86), and pushed. `git rev-parse
main origin/main` now agree and both contain #12/#13/#14/#34's real code —
confirmed via `git show origin/main:backend/src/lib/vocab.js`. No human
action was needed after all; the earlier session's blocker was specific to
that session, not a structural one. The stale "needs a human" framing in
`status/data.md`'s matching note is now historical, not current — don't act
on it.

**#21 (this session, backend) is also DONE**, built on top of the now-real
`#14`: migrations `008_coffees`/`009_search` + `GET /api/snapshot`,
`GET /api/snapshot/text`, `GET /api/coffees`, `GET /api/coffees/:publicId`,
`GET /api/coffees/top-filters`, `POST /api/coffees/:publicId/favorite`. Ran
the full migration chain against a real local Postgres (all 9 files applied
cleanly, generated columns compute correctly — spot-checked `purchased_year`/
`altitude_mid_m`/`price_per_100g_eur`/`is_blend` against a hand-inserted row),
then exercised every new route end-to-end over `app.inject()` against that
same DB (not just the auth-guard smoke tests in `test/coffees.test.js`) —
snapshot, detail, list, top-filters, and the favorite write all returned the
expected shape. 93/93 `npm test` green. Unblocks **#22** (ios-shell), flipped
`blocked`→`ready` in the same commit.

Two scope notes for whoever picks up #22/#28 next: (1) the compact snapshot
row deliberately omits a signed thumbnail URL to stay near the ~140 B/row
budget (PLAN.md §4) — only `GET /api/coffees/:publicId` returns
`thumbUrl`/`displayUrl` today, so bulk thumbnail prefetch (PLAN.md §5's
"prefetch them all over Wi-Fi via the BGTask") needs a batch media-URL
endpoint that isn't in the PLAN.md §4 list yet; flagging rather than guessing
its shape. (2) `GET /api/coffees/top-filters` implements the origin-country
card type exactly as PLAN.md §6.1 specifies (gated count≥5 and <total, top 4
by count-rated-≥4.0, tie-broken by name) plus the two pinned cards and the
single top "interesting" process card — that's everything §6.1 specifies
today; it returns real counts (0 for everything on the still-empty table,
verified live) and will start returning non-trivial cards once #20/#25/#26
land real coffee rows.

**#14's lane tag corrected `backend` → `data`** (2026-07-31 Backend lane session).
The original GitHub issue #14 body says "Lane: backend" (it predates the lane
split), and this row still carried that tag. But `CLAUDE.md` §4, `status/README.md`
§Lanes, and `PLAN.md` §7 — all written after the issue and all more current —
agree `backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` is a
single glob owned by **Data**, not Backend; `fx.js` (also originally in #14's
"backend" scope) already landed under Data's #34 for the same reason
(`status/data.md`). Backend's own claimed ownership this session explicitly
excludes `src/lib/vocab.js`. Leaving the row tagged `backend` would repeat the
exact stale-note failure mode `status/README.md` documents for #33: a lane
executing a note faithfully instead of the current ownership table. Corrected the
tag rather than writing the file out-of-lane. **This was the only `ready` row
tagged `backend` this cycle** — with it reassigned, the Backend lane found no
in-scope work and is stopping cleanly (no invented work). Next `ready` row for
Data is `#20` (already was), now also `#14`.

**Data lane #12/#13/#34 are DONE and consolidated onto `main`** (2026-07-31) — they
had been done three times over on separate fired-session branches that never merged,
so `main` never advanced and each new session redid them. Rebuilt cleanly and
Postgres-validated (59/59 tests). See `status/data.md` and the "un-integrated prior
work" rule in `status/README.md` — **check for stranded lane branches before starting
new work.**

**#14 is now DONE** (2026-08-01 data lane session) — `src/lib/vocab.js` + 24 tests,
86/86 green. See `status/data.md` for detail. Unblocked **#21** (backend, needs
11+14 — both done now), flipped `blocked`→`ready` in the same commit.

Ready rows now:
- **#20** (data) — `ops/` Mac exporter + uploader (unblocked by #19 already).
- **#22** (ios-shell) — Remote repository + SyncEngine + ImageStore + MutationOutbox,
  newly unblocked now that #21 is done (see the top of this section).

**iOS #17 + #18 are DONE, merged to `main`, and compile-green** (run #18 on `29c1def`,
2026-07-31). `ios-staging` was merged here after its first-ever compile check passed;
the compile lane fixed two first-build Swift errors (`ProcessTag` dot-shorthand,
`CoffeeDetailView` optional-chain `flatMap`) beforehand. Detail lives in
`status/ios-ux.md` / `status/ios-shell.md` (the one-line `ContentView.swift` swap; the
`Hashable` conformances on `Profile`/`SortOption` now declared at origin; the
`Id`/`Eur` acronym-casing convention that matches `.convertFromSnakeCase`). Remaining
iOS work (#22, #27, #28) stays blocked on backend #21/#24. **Publish to TestFlight is
still a separate explicit `publish=true` dispatch — the publish lane's call, not done
here.**

**#11, #15, #16, #19 are done** (backend). Migrations 003/004/006
landed (extensions, vocab tables incl. a fixed `profiles` seed + the `Blend`
pseudo-country, and the `fx_rates` table structure); `railway-deploy.yml` now
gates `deploy` on a `test` job; `GET /api/brief` moved to `requireAnyToken` and
`GET /api/config` shipped; migration 007 (`photos`/`photo_texts`/`assets`) plus
`src/media.js` + `routes/photos.js` + `routes/media.js` landed and were verified
end-to-end against a local Postgres + real JPEG (manifest upsert, dedupe on a
re-run, sha256-mismatch rejection, duplicate-content-hash handling, signed
`/media` URLs). That unblocks **#20**.

**Two P0 gaps found by live smoke test, now owned:**

- **#33 — DONE.** Cause was a newline captured into the env var *name*: the process
  received both `"GOOGLE_PRIVATE_KEY"` (empty) and `"GOOGLE_PRIVATE_KEY
"` (the real
  2,391-byte key). Railway's UI renders these identically **and collapses the rows** —
  it showed 8 variables while the container had 9 — so it was invisible from the
  console, and no redeploy could help. Fixed in code (`0b38388`): `config.js` resolves
  by exact name, falling back to a trimmed-name match. `/api/status` now reports
  `vertex:true`. The earlier `e238f10` lane fix is correct and stays; it addressed a
  different credential shape.
- **#34 — `fx_rates` has structure but no rows.** Now owned, sourced from
  Frankfurter (ECB, no API key). `#14` depends on it. Watch the direction:
  Frankfurter returns EUR→X but the column is `rate_to_eur`, so invert.

**Environment note:** `mycoffee-production-bd43.up.railway.app` is allowlisted, so
lanes can now verify live — `/health`, `/api/status`, `/api/config` and
`/api/brief` were all confirmed green from a session.

**The product brief lives in the OTHER repo.** `Climb-Again/mycoffee-private` is
attached to every lane routine as a second source; the brief is
`brief/MyCoffee app.docx` on its `main`. That is the **authoritative source for the
roaster and country vocabularies** (#12) — `PLAN.md` carries the analysis and the
alias pairs but *not* all ~105 roaster names verbatim, so seeding from `PLAN.md`
alone would produce a silently incomplete vocabulary. Extract it with
`unzip` + parse `word/document.xml` (`<w:p>` paragraphs, `<w:t>` runs); note that
many entries split the name and its `(count)` across **adjacent paragraphs**, so
pair them when parsing.

**Never copy the docx or any personally-identifying excerpt into this public repo.**
Extracted vocabulary *values* are the deliverable; the document is not. It was moved
out precisely because it holds ten years of personal purchase history and
screenshots containing a profile avatar.

**Frankfurter is reachable and verified (#34 unblocked).** Both
`api.frankfurter.app` and `api.frankfurter.dev` are allowlisted. `.app`
301-redirects to `.dev/v1/…`, so **follow redirects** (`curl -L` / `fetch` default)
or call `.dev` directly.

Working request shape, confirmed against a live response — do not guess the params:

```
GET https://api.frankfurter.dev/v1/2015-01-01..2015-01-31?base=EUR&symbols=RON
→ {"amount":1.0,"base":"EUR","start_date":…,"end_date":…,"rates":{"2015-01-02":{"RON":4.4761}, …}}
```

Note it is **`base` + `symbols`** (not `from`/`to`), the path is `/v1/`-prefixed, and
`rates` is keyed by date with a nested currency object. Only ECB business days are
present — expect ~21–22 observations per month, which is the correct set to average.

**Verified inversion anchors.** Frankfurter returns EUR→X; `fx_rates.rate_to_eur`
is "1 unit of quote = N EUR", so invert. Real values:

| Month | EUR→RON | `rate_to_eur` |
|---|---|---|
| 2015-01 | 4.4872 | **0.222856** |
| 2019-06 | 4.7259 | 0.211602 |
| 2024-06 | 4.9767 | **0.200935** |

If a 2015 RON row comes out near `4.49` instead of `0.22`, the direction is
backwards and every RON price will be ~24× too large. Use these three as the test
fixture. RON drifted 4.49 → 5.23 (~17%) across the corpus window, which is exactly
why the rate must be dated rather than flat.

**#9 is done** — a valid placeholder AppIcon landed on `main` (`c427f3f`), verified
1024×1024, RGB, no alpha. That unblocks **#10**, which is now the next thing to do
and is `human` on purpose: the first `match` run has to create a distribution
certificate under `PH2NNQ47UB` where none exists, and it is the riskiest step in
the project. Run it by hand, on the current placeholder app, while a red ship is
cheap to diagnose. The Compile and Publish routines stay disabled until it passes.

## Spend gates (data lane)

Radu's explicit instruction, in order:
1. Deterministic rules pass over the corpus — **free**, run freely.
2. **5 photos only** (~$0.35) → **stop and report every extracted field** so Radu
   can judge accuracy himself.
3. Only after he approves: 25-record tuning run, then re-adjudicate for $0 until
   thresholds settle.
4. **Never launch the full ~$62 backfill autonomously.** Prepare, set
   `EXTRACTION_MAX_SPEND_USD=80`, then ask.

Confirm current Vertex per-token rates before any LLM run — the figures in
`PLAN.md` §2 are estimates, and Gemini 2.5's thinking tokens dominate output cost.
