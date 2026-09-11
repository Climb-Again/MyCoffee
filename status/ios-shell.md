# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-shell-history.md`](archive/ios-shell-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

_none_

## Abandoned

_none_

## Session notes

- **2026-09-11 (interactive session, Radu: "analyse all lanes… already implement
  some of the features and solve any blockers") — #113 and #114's shell half
  done; `ios-staging@ae61f7e`, compile-green at run #112.**

  **#114** was two config blockers the row itself flagged as coming first, and
  both were real: `project.yml` had `TARGETED_DEVICE_FAMILY: "1"`, so the app
  ran letterboxed in iPhone compatibility mode on iPad and **no amount of
  layout work would have been visible**; and `Info.plist` declared portrait
  only, so it never rotated on any device. Now `"1,2"` plus landscape on
  iPhone and a `~ipad` variant with all four (iPadOS requires all four of an
  app that doesn't opt out of multitasking via `UIRequiresFullScreen`). The
  AppIcon needed nothing — it is a single `universal`/`platform: ios` 1024²,
  which already covers iPad. The layout ramp is `Features/**`, so it is now
  **#191** on ios-ux rather than an implied remainder of a "done" row.

  **#113** looked like "add an enum case" and wasn't. The value band is a
  **library-wide quintile**, so every coffee's score must exist before any one
  coffee's band can — and `CoffeeIndex.init` computed the value scores *after*
  `buildPostings`. Moving them before it is the whole change; `valueScoreByRow`
  / `valueBandByRow` then fall out as parallel arrays, and `valueBand(for:)`
  becomes a lookup instead of two binary searches per visible row.
  `SortOption.value` has the same shape of problem: it cannot be decided from
  two `Coffee`s, so `coffees(matching:sortedBy:)` intercepts it and a new
  `CoffeeIndex.sectionLabel(for:sort:)` supplies the band. The new
  `valueBand:` parameter on `SortOption.sectionLabel` **defaults to nil**
  specifically so no pre-existing call site changed signature.

  Seam edits into UX files per CLAUDE.md §4 (`CoffeeDisplay.swift`'s
  `FilterDimension.title` / `facetLabel` / `SortOption.displayName`) — but not
  left as stubs: **#138 shipped in the same session**, so the pills toggle and
  the sort headers read properly. Also moved the verdict wording onto
  `ValueRating.Band.label`, which deletes the two hand-rolled `verdictLabel`
  copies #181 had flagged.

- **2026-09-11 — #156 done this session (Brew lab shell surface: models,
  wire, store, outbox, query).** `Models/BrewOption.swift` (`BrewKind`,
  `BrewOption`, `BrewRecipeSpec` incl. `ratio`/`summary`, `BrewTrialState`);
  `API/Wire/BrewWire.swift` (`BrewOptionDTO`, `BrewRecipeSpecDTO`,
  `BrewStateResponseDTO`); `VocabDTO.brewOptions` (lenient, `[]` default) and
  `CompactCoffeeDTO`/`CoffeeDetailDTO.brewTried`/`brewBest` (both `[Int]?`).
  `Coffee.brewTriedIds`/`brewBestIds` are `[Int]?` (not the spec's literal
  non-optional `[Int]`) with `triedBrewOptionIds`/`bestBrewOptionIds`
  nil-coalescing accessors — same pattern as `rotationQuarterTurns`/
  `rotationTurns`, chosen over a hand-written `CodingKeys`/`init(from:)` for
  `Coffee` (which has ~30 fields and explicitly avoids a parallel
  `CodingKeys` enum per its own doc comment) purely because the synthesized
  decoder already does `decodeIfPresent` for `Optional` properties for free;
  behavior is identical (missing key -> reads as "nothing tried"). `Coffee.withBrew(tried:best:)`.
  `Vocabulary.brewOptions: [Int: BrewOption]` + `brewOptions(of:includeArchived:)`
  + `brewOption(kind:value:)` + `insertingBrewOption(_:)`; no `PersistedSnapshot`
  schema bump (`decodeIfPresent … ?? []`, same class of fix as `Coffee`'s fields).
  `APIClient.brewOptions/createBrewOption/updateBrewOption/setBrewState`.
  `SyncEngine`: `setBrewState` optimistic+outbox (mirrors the server's
  `nextTrialRows`/`impliedTrials` state machine locally, including the recipe
  auto-tick), `createBrewOption`/`updateBrewOption` confirmed+throwing;
  `pendingBrewStates(for:)` applied over both `sync` and `loadDetail`.
  `MutationOutbox.flush` now returns `[FlushedBrewState]` (was `Void`) so a
  successful brew POST's whole-state response can replace the coffee's local
  arrays — every other call site (`setFavorite`/`resolveReview`/
  `dismissReview`/`sync`) now goes through a new private `SyncEngine.flushOutbox`
  wrapper instead of calling `outbox.flush` directly, so the reconciliation
  isn't duplicated per call site. `CoffeeIndex.bestBrewOption/triedBrewOptions/
  brewState/brewWinRates`. `CoffeeStore.setBrewState/createBrewOption/
  updateBrewOption` + `brewErrorText`. `SampleCoffeeRepository`/`SampleData`
  got a small real fixture (3 recipes, 4 devices, a few grind/temp rows, two
  sample coffees ticked) — `createBrewOption`/`updateBrewOption` still throw
  `.notConfigured` in the sample repo (no fixture logic to fake a rename),
  same stance as `editField`.

  **Query half for #158, shipped in the same row per the spec:**
  `FilterDimension.brewDevice/.brewRecipe/.brewGrind/.brewTemp`, postings over
  **tried** ids, `CoffeeFilter.brew{Device,Recipe,Grind,Temp}IDs` +
  `isEmpty`/`clearing`.

  **Seam edit (CLAUDE.md §4) in `Features/Coffees/CoffeeDisplay.swift`
  (ux-owned) — recorded here and in `status/ios-ux.md`:** added the 4 new
  cases to `FilterDimension.title`'s exhaustive switch (plain labels: "Brew
  device"/"Brew recipe"/"Grind size"/"Water temp") and to `facetLabel`'s
  nested `.vocabID` switch (resolves `vocabulary.brewOptions[id]?.label`
  instead of falling through to "Unknown" — trivial and correctness-only, no
  styling). Deliberately did **not** touch `FilterSheetView.swift`'s
  `toggleFacet`/`isFacetSelected` — both already have a `default:` arm so
  they compile untouched; wiring an actual tappable "Brew lab" filter group
  is #158's UX work, not required for `ios-staging` to stay green.

  **No unit test target exists in this project** (`ios/project.yml` only
  defines the `MyCoffee` application target — no local Xcode/Simulator
  either), so the spec's ask to "prove [no schema bump] with a pre-change
  fixture test" isn't mechanically checkable here; verified instead by
  reasoning through the decode path (every new/changed field is
  `Optional`-typed or defaults via `decodeIfPresent`) the same way every
  other backward-compat fix in this file has been.

  Not done: #157 (the UX feature — coffee-page section, `BrewLabSheet`,
  Settings catalogue) and #158 (filter UI + Insights card) — both ios-ux,
  now unblocked (#157 flipped `blocked` → `ready`).

- **2026-09-09 — #117(a)/#136/#139 done this session** — see `BACKLOG.md`'s own
  DONE notes for implementation summaries (unknown-postings fix for the four
  band filter dimensions, the `POST /api/coffees/evaluate` client surface, and
  the 65/35 value-algorithm reweight). One correctness find worth restating
  here since it changes what a future evaluate-screen session should expect:
  **`fields.profileId` in the evaluate response is a slug STRING
  (`Profile.rawValue`-compatible), not a numeric vocab id** — the backend
  variable name is misleading; verified by reading `adjudicate.js`/
  `normalize.js`, not assumed. Also found (not fixed, not this lane's file):
  `AltitudeBand.bands`'s "either min or max nil ⇒ Unknown" guard doesn't
  quite match `InsightsAggregation.dataQuality`'s "both nil" missing-count —
  pre-existing, harmless today, flagged in #117's DONE note.

  **#113 and #137 (value-band filter/sort) are NOT done — found a real
  cross-lane compile blocker, not just a "needs ux to consume it" seam.**
  Both rows ask for new cases on `FilterDimension`/`SortOption`/`FacetKey`
  (shell-owned, `Query/**`), but `Features/Coffees/CoffeeDisplay.swift`
  (ux-owned) has three *exhaustive*, no-`default` switches over exactly
  those three types (`SortOption.displayName`, `FilterDimension.title`,
  `facetLabel(_:dimension:vocabulary:)`). Adding the cases alone breaks
  `ios-staging`'s compile the moment they land, and this lane isn't allowed
  to add the missing switch arms in `Features/**` to fix it. Documented in
  both rows in `BACKLOG.md` rather than picking one side and creating a red
  build — this needs the two iOS lanes to land their halves in the same
  wave (or at least in immediate succession within one push), not the
  normal independent-cadence pickup. Left both `ready`.

- **2026-09-07 — RETRACTED: a "stranded branch" finding earlier this session
  was my own git mistake, not a real problem.** Mid-session I flipped
  `#118`/`#130`/`#131` to `blocked` and un-claimed `#130`, believing
  `a73b520` (#118's backend route) existed only on `origin/claude/adoring-ride-2q9qas`
  and not on `main` — based on `git merge-base --is-ancestor a73b520 origin/main`
  failing. That check ran against a **stale local `origin/main`**: this session's
  container never ran `git fetch origin main` before the check (only
  `git fetch origin ios-staging`, earlier), so the local `origin/main` ref was
  whatever the container started with, not current. A later `git fetch origin main`
  showed `a73b520` (and the whole ~30-commit range I'd flagged) **is** an
  ancestor of the real `origin/main` — #118 was correctly `done` all along, and
  the "production running an out-of-band deploy" alarm was wrong too (the
  `quick-create` 400 response was just main's own deployed route). Reverted
  `#118`/`#130`/`#131` to their original status in `BACKLOG.md`. Sorry for the
  noise — flagging the mistake here so nobody wastes time chasing a phantom
  merge. Lesson for next time: fetch every ref you're about to diff against,
  not just the one you're checking out.

- **#109/#112/#130 done this session** — see `BACKLOG.md`'s own DONE notes for
  implementation summaries (value-meter rework, the row-render perf fix, and
  the quick-create client wiring). #113 (value band in filters/sort/tiebreaker)
  is now `ready`, unblocked by #109+#112; left for a future session — it's a
  bigger architectural change (postings + `SortOption` need `CoffeeIndex`
  access they don't have today) that deserves its own claim rather than being
  squeezed in after this session's detour. #131 (ios-ux) is unblocked by #130.
  Session notes below are for #112's predecessor, #95:

- **2026-08-28 — #95 value meter is now quality-for-money (`UPDATE_BRIEF.md` §B).**
  `CoffeeIndex.valueBand(for:)` scored **price alone** — the coffee's
  `pricePer100gEur` quintile, inverted — so a cheap bag rated 3.2 read
  `FAIR VALUE`, which is backwards. It now buckets the library into five price
  bands, and inside a coffee's own band compares its rating to the mean rating of
  your bags there: pills are its rating rank within the band, the verdict comes
  from `delta = rating − bandMean`. Unrated or unpriced returns `nil` — no meter
  at all, where the old version still gave an unrated bag a verdict.
  `ValueRating.Band` gains `.overpaid` (replacing `.pricey`) and `band` is now
  **optional**, `nil` meaning "too few rated bags in this band to judge" —
  pills without a verdict rather than a guess.

  **The threshold was measured, not guessed.** Across the 94 rated-and-priced
  coffees, ±0.20 splits them ~26% overpaid / ~48% fair / ~27% great, which is the
  "clearly above / around / clearly below" the brief asks for; ±0.10 gives
  39/28/33 (trigger-happy) and ±0.30 gives 15/67/18 (timid). Band means rise
  3.95 → 4.40 across bands 1–4 then dip to 4.24 in band 5, so the metric does
  carry signal — pricier is not automatically better-liked.

  Two things worth knowing. **Only 94 of 411 coffees are both rated and priced**,
  so the meter is absent on roughly three quarters of the library by design.
  And per-band rating spread varies a lot (SD 0.15 in the cheapest band vs 0.40
  in the priciest), so one absolute cutoff is slightly harsher on the tight band;
  if that ever reads wrong the next refinement is scaling by each band's own SD.
  Both are recorded in the code comments.

  Band stats are precomputed in `CoffeeIndex.init` so `valueBand(for:)` stays
  O(log n) per row instead of rescanning the library for every visible cell.
