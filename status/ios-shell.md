# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-shell-history.md`](archive/ios-shell-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

_none_

## 2026-09-14 (interactive, "run all lanes") — #178 shipped; seam edits taken by ios-ux for #201/#195

**#178 (a)(b)(c)(e) shipped, compile-green run #134.** Full write-up in the
backlog row. Two things worth carrying forward:

* **(d) was not done, and the row's own claim is partly wrong.** It lists
  `extractWizardDraft`/`createWizardCoffee` as callerless; they are the
  `CoffeeStore` end of a `CoffeeRepository` protocol requirement implemented by
  both `RemoteCoffeeRepository` and `SampleCoffeeRepository`. And
  `SampleData`/`SampleCoffeeRepository` are referenced only from doc comments,
  but `SampleData` was edited two commits earlier (#203, `41d5180`) to give the
  DAK sample roaster a live `logoUrl` "so the tile has something to render in
  sample mode" — someone believes sample mode is reachable. Deleting either on
  the strength of a grep would be guessing; verify before the cleanup row.
* **`Coffee.purchasedOn` stays non-optional on purpose.** #178(b) makes the DTO
  optional and counts the drop, but widening the model ripples into the
  canonical sort, the year facet and three Insights aggregations — ~15 UX-owned
  call sites. Measured 0 of 414 live rows affected, so it is latent; the
  wizard's `quick-create` path (a photo with no `captured_at`) is how it starts.

**Seam edits taken by ios-ux this session, recorded here per CLAUDE.md §4:**

* `API/APIClient.swift` — `whatsNewSeen()` / `setWhatsNewSeen(key:seen:)` (#201)
  and `shortlist()` (#195); `API/Wire/WhatsNewWire.swift` — three DTOs.
* `Store/CoffeeStore.swift` — `RootTab.recipes` / `RootTab.shop`, and
  `shortlist` / `shortlistError` / `loadShortlist()` (#195).
* `Models/Shortlist.swift` — new. Every field optional except the url, because
  the server stores the extension's payload opaquely and the two ship on
  different schedules.

All thin wrappers over existing `send`/`makeRequest` — no new shell logic.

## Abandoned

_none_

## Session notes

- **2026-09-14 — seam edit for #203 (ios-ux lane): `SampleData.swift` gives
  the DAK sample roaster a real, live `logoUrl` (production
  `ops/roaster-assets/logos/dak-coffee-roasters.webp`) so `RoasterLogoTile`
  has something to render in sample mode. One line, no new shell logic.
  Landed `41d5180` alongside ios-ux's `RoasterLogoTile`/`Symbols` changes.**

- **2026-09-14 — seam edit for #180 (ios-ux lane): `CoffeeMapping.swift`'s
  compact mapping stops seeding `images.display` from `thumbUrl`, using the
  empty-string sentinel `CoffeeDetailDTO.makeCoffee` already uses for a
  missing URL instead (`?? ""`), so a coffee page's hero doesn't render a
  blown-up 320px thumb before the detail fetch supplies the real photo. One
  line, no new shell logic. Recorded per CLAUDE.md §4's seam rule; ios-ux did
  the restyle-side work (`CachedImage.swift`, the three call sites) in the
  same commit, `30889bb`.**

- **2026-09-14 — #176(a)(b, partial)(c)(d), #177, #204 done this session;
  #178 left `ready`. Compile-checked green: `ios-staging@b6d39b5`,
  run #128 (https://github.com/Climb-Again/MyCoffee/actions/runs/34806170310),
  succeeded.**

  **#176 main-thread/rebuild hygiene:**
  **(a)** `SyncEngine.init` no longer calls `PersistedSnapshot.load()`
  synchronously — it was running on the *main* thread, not just off-main-not-
  actually: `SyncEngine()` is constructed as `RemoteCoffeeRepository`'s stored
  property default, which is itself constructed as `CoffeeStore`'s default
  argument, evaluated inside `CoffeeStore.init` — `@MainActor`. So the ~1.3 MB
  decode ran on the UI thread before the app ever drew a frame. Replaced with
  `loadPersistedIfNeeded()`, called at the top of every actor method that
  touches the persisted fields (`currentIndex`, `sync`, `loadDetail`,
  `setFavorite`, `setBrewState`, `createBrewOption`, `updateBrewOption`,
  `setRotation`, `quickCreateCoffee`, `flushOutbox`) — first call after actor
  construction does the decode, on the actor's own executor, off main. Missing
  this guard on any state-touching entry point would silently reset `coffees`
  to disk-only data mid-session, so it's deliberately on every one rather than
  just `currentIndex` as the backlog row's own wording suggested.

  **(b), fold-once half only:** `CoffeeIndex.searchKey` no longer folds
  `searchTexts`' ~894 KB blob on every index rebuild (every favourite toggle,
  brew tick, or single-coffee detail merge rebuilds the whole index) — it now
  folds only the per-coffee metadata and appends the already-folded text.
  `SyncEngine` folds `searchTexts` exactly once, at the two points it's
  populated: `loadPersistedIfNeeded` (defensively, since a pre-existing
  on-disk snapshot predates this change and holds raw text) and `sync`'s
  network merge. Folding is idempotent, so folding an already-folded string
  a second time is wasted work but not a correctness risk.
  **NOT done: the "run `replacingCoffee` in `SyncEngine`" half.** That needs
  `CoffeeRepository.loadDetail`/`editField`/`editFields`/`createCoffee` to
  return a rebuilt `CoffeeIndex` instead of a bare `Coffee` (a protocol change
  touching `CoffeeRepository.swift`, `RemoteCoffeeRepository.swift`,
  `SampleCoffeeRepository.swift`, and every `CoffeeStore` call site) — real
  value, but a bigger, riskier change than the rest of this batch and not
  something to land unverified in the same commit as everything else here.
  Left as an explicit follow-up rather than silently dropped; #176 is not
  re-filed since the row already exists and still describes it accurately.

  **(c)** `loadDetail`'s `persist()` is now `schedulePersist()` — debounced
  400 ms, cancelling any still-pending write, so browsing quickly between
  coffee pages coalesces into one encode+write instead of one per open. Sync's
  own end-of-sync `persist()` stays immediate (infrequent, not a rapid-fire
  UI action).

  **(d)** `topRoasterIDs`/`topOriginCountryIDs` were re-filtering *and*
  re-sorting their rating tally on every call, and both are called from every
  visible row's `body` (`CoffeeRowView.isTopRoaster`/`.originAverage`) with two
  different `minCount`s (5, 3) in live use. Precomputed each as a `minCount: 0`
  average-sorted array in `init`; both accessors are now a `filter` over an
  already-sorted array (order-preserving, no re-sort) rather than a fresh
  sort per call. Removed the now-unused raw tally properties.

  **#177 ImageStore:** added an `NSCache<NSString, CGImage>` keyed
  `(cacheKey, maxPixelSize)` so a re-requested (url, size) pair — which
  `Thumbnail.swift`'s `.task(id:)` does on every scroll-in — skips the decode
  entirely; moved the actual `CGImageSourceCreateThumbnailAtIndex` decode into
  a `private static` (non-isolated) function run via `Task.detached`, so
  concurrent thumbnail requests decode in parallel instead of serializing
  through the actor one at a time; `loadData`'s disk-cache-hit path now
  mtime-touches a key at most once per launch (`touchedThisLaunch: Set<String>`)
  instead of on every read. Added `ImageStore.displayMaxPixelSize` (1080 px) —
  a named constant for the "display" tier so the hero/zoom/review call sites
  (#180, iOS UX — NOT touched here, `Features/**` is UX-owned) can route
  through `thumbnail(for:maxPixelSize:)` with one shared cache key instead of
  each screen picking its own size. Also moved `evictStaleEntries()` to run
  after every `sync()` (fire-and-forget), not only at launch (`RootView`,
  unchanged) — a cache that crossed 30 MB mid-session used to stay over
  budget until the next cold start.

  **#204** `Roaster.CodingKeys.countryId` had an explicit raw value
  (`= "country_id"`), which is exactly wrong under
  `.keyDecodingStrategy = .convertFromSnakeCase` (`CoffeeCoding.swift`): that
  strategy converts the JSON key `country_id` → `countryId` *before* matching
  it against a `CodingKey`'s `stringValue`, and the explicit raw value's
  `stringValue` is still `"country_id"` — so it never matched and every
  roaster's `countryId` silently decoded to `nil`. Dropped the raw value
  (`case countryId`, letting the strategy do the conversion) — same fix shape
  the row's own diagnosis specified. No unit test target exists in this
  project to add the requested decode-fixture test (`status/ios-shell.md`'s
  standing note); grepped the rest of `Vocab.swift` and every `API/Wire/**`
  file for the same `case x = "snake_case"`-under-`.convertFromSnakeCase`
  pattern — the only other hit, `Profile.coFermented = "co_fermented"`, is an
  enum **raw value** (the wire *value*, not a coding key), which
  `.convertFromSnakeCase` never touches, so it isn't the same bug.

  **#178 (shell hygiene batch) left `ready`, not attempted.** Five sub-items,
  several genuinely risky to land unverified in one sitting: (a) replacing
  `Coffee`'s 35-argument initializer at six call sites across three files with
  a `with(_ mutate:)` builder: (b) `purchasedOn` optionality + a new debug
  counter; (c) new `@Published lastSyncError`/`lastSyncedAt`; (d) deleting
  dead code across four files including `SampleData.swift`/
  `SampleCoffeeRepository.swift`; (e) consolidating five separate ad-hoc
  `APIClient` construction sites behind one shell entry point. Each is
  plausible on its own but this session already made four separate,
  independently-verifiable changes across `SyncEngine`/`CoffeeIndex`/
  `ImageStore`/`Vocab.swift`; picking up #178's cross-file initializer rewrite
  in the same sitting risked a red compile nobody could quickly attribute to
  one change. Next ios-shell session: lowest phase first still puts #178
  next.

- **2026-09-12 — #175 done this session (sync hygiene, all five sub-items).**
  **(a)** `/api/snapshot/text` (~95% of sync bytes, no `since` of its own) now
  sends `If-None-Match`; `APIClient.snapshotText(ifNoneMatch:)` returns
  `(texts: [String: String]?, etag: String?)`, `texts` `nil` on a 304 so
  `SyncEngine.sync` skips the ~300 KB decode and keeps its current
  `searchTexts`. New `APIClient.sendRaw`/`sendConditional` (private) accept
  304 alongside 2xx and surface the response `ETag`; `/api/snapshot` itself is
  untouched — its `since` param changes every call, so a stable conditional
  GET against it needs the server half (#168), same as the row's own note.
  New `PersistedSnapshot.searchTextsETag: String?` persists it (schema-safe:
  `Optional`, decodes `nil` from an old file with no such key). **(b)**
  `CoffeeStore.load()` now guards its own re-entrancy with a private
  `isLoading` flag instead of relying solely on the two UX call sites'
  `index.coffees.isEmpty` check — both can fire before either completes on
  cold start, so that check alone let two `refresh()`s (and two
  `snapshotText` fetches, pre-(a)) run serially through the actor. Left
  `RootTabView`/`CoffeesListView`'s `.task`s untouched: this isn't the
  enum-case seam rule (nothing there stops compiling), and the idempotency
  guard alone removes the double fetch. **(c)** `SyncEngine.setFavorite` now
  awaits only `outbox.enqueueFavorite` (in-memory, fast) before returning the
  already-mutated `currentIndex()`; the actual `flushOutbox` network call
  runs in a detached `Task` instead of being awaited, so offline the heart
  flips immediately instead of waiting up to the outbox's ~60 s timeout.
  Confirmed this is safe for favorites specifically: `flushOutbox`'s only
  side effect beyond removing the queued mutation is reconciling a flushed
  *brew*-state response into `coffees` (`FlushedBrewState`), which a
  favorite-only flush never produces. Left `setBrewState`'s identical
  await-before-return shape alone — same latency smell, but out of this
  row's scope (only "the favorite toggle" is named) and detaching it would
  drop the brew reconciliation's publish, which needs its own care. **(d)**
  New `SyncEngine.lastFullSyncAt` (persisted, `Optional`/schema-safe) forces
  `sync` to fetch `since: nil` at least every 14 days, covering the
  schema-mismatch-forced-refetch case too (both now flow through one
  `requestedSince == nil` check) — keeps every coffee's signed `thumbUrl`
  (30-day expiry, `coffees.js:62`) renewed well before `ImageStore`'s 30-day
  eviction can turn a 403 into a permanent placeholder, even for a coffee a
  delta sync would otherwise never re-send. **(e)** Decided: **deleted the
  ghost**, did not register a real BGTask. `BGTaskSchedulerPermittedIdentifiers`
  (and `UIBackgroundModes`, equally vestigial — grepped: no
  `BGTaskScheduler`/`BGAppRefreshTask`/`BGProcessingTask`/background-fetch API
  is called anywhere in the app) removed from `Info.plist`; the two comments
  in `MyCoffeeApp.swift`/`ImageStore.swift` that referred to "a BGTask that
  may never fire" reworded to state plainly that eviction only runs at
  launch. Rationale: building actual background refresh is a materially
  bigger feature (registration, a launch handler, battery/network
  considerations) than this hygiene row's scope, and isn't testable without
  local Xcode/Simulator (`ios/project.yml` has no test target) — if Radu
  wants real background sync, that's a fresh backlog row, not a default this
  lane should assume. No unit test target exists to add coverage to (same
  gap noted in #178's session entry); reasoned through each change instead —
  the ETag/304 path was checked against `sendRaw`'s explicit 304 allowance,
  the idempotency guard against the actor-hop timing (the guard-then-await
  split has no suspension point before `isLoading = true` lands), and the
  detached-flush safety against reading `MutationOutbox.flush`'s actual
  reconciliation logic rather than assuming. `ios/MyCoffee/Info.plist`,
  `Sources/{App,API,Store}/**`.

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
