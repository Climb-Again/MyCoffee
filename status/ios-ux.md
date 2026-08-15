# Lane: iOS UX

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Session notes

- [2026-08-15 UTC, later session] Integrated #50 with the off-lane #52 redesign, then landed #53/#54/#55 — branch `ios-staging`
  - **Integration, not new scope, came first.** Merging `origin/main` into `ios-staging` conflicted in
    `Features/Insights/{InsightsCharts,InsightsView}.swift` — both branches had edited the same files
    off the same parent commit (`5b23df7`): this lane's own `#50` (tap-to-filter + per-label average,
    `348b8cc`, on `ios-staging`) and `#52` (the Insights 3-tab/time-window redesign, `85d6911`,
    **committed directly to `main`, never through `ios-staging`** — a real instance of the exact
    "commits bypass the dev branch" footgun `CLAUDE.md` §12 already warns about, just in the
    `main`-instead-of-`claude/*` direction this time). `status/BACKLOG.md`'s own copy on `main`
    still showed `#50` `ready` (unaware `348b8cc` had landed on `ios-staging`); `ios-staging`'s copy
    had no idea `#52` existed at all. Resolved by keeping `#52`'s windowed 3-tab structure (it's
    what's live in production/TestFlight) and re-threading `#50`'s `PieSlice.key`/`onSelect` tap
    wiring through the windowed `chartsSection` and `slices(for:facets:)`; kept `#52`'s "Other
    carries no average" decision over `#50`'s own draft weighted-average variant, since `#52` is the
    already-shipped behavior and the row didn't ask for an Other average, just per-label + tap.
    `RootTabView`'s `TabView(selection:)` wiring and `FilterSheetView`'s new `(.decaf, .bool)` case
    (both part of `#50`) survived the merge untouched — neither conflicted with `#52`. Flipped `#50`
    to `done` (it always was, just not visible from `main`'s stale copy), `#51`/`#52` to their
    already-true `done`, in `status/BACKLOG.md`. Pushed the merge (`8cbeb5c`) before writing any new
    code, per the integrate-before-you-start rule.
  - **53 (findings deep-link)**: `InsightsFinding` gained `subjectText`/`subject: FindingSubject?`
    (a `dimension`+`FacetKey` pair), populated only for categorical findings (profile, decaf, origin
    country, roaster country, roaster) — ordinal findings (altitude/price/year) have no single
    filterable value, so both stay `nil` and those sentences render as plain text. The view builds
    an `AttributedString` per finding and marks just the `subjectText` span with a `.link` attribute
    (a synthetic `mycoffee-finding://<finding-id>` URL) rather than splitting the sentence into
    separate `Text`/`Button` views — that would have broken natural line-wrapping mid-sentence. An
    `.environment(\.openURL, OpenURLAction { ... })` on `findingsSection` intercepts taps on that
    scheme, looks the finding up by id, and calls the same `selectInCoffees(dimension:key:)` `#50`
    already built for the Charts tab's legends — no new deep-link mechanism, straight reuse.
  - **54 (data-quality deep-link)**: `InsightsAggregation.DataQualityField` gained
    `dimension: FilterDimension?` — set for the six fields with a real Unknown facet (Rating,
    Process, Origin country, Roaster country, Altitude, Price), left `nil` for Weight (not a listing
    facet at all — the row's own called-out exception). `DataQualityCard` wraps a row in a `Button`
    only when `dimension != nil`; the rest render as plain, non-interactive text exactly as before.
    New `InsightsView.selectUnknownInCoffees(dimension:)` builds a fresh `CoffeeFilter` with just
    that dimension's Unknown bucket selected (not layered onto whatever filter was already active,
    same "replaces" semantics as `#50`/`#53`) and switches to Coffees.
  - **55 (review photo zoom)**: confirmed the row's own diagnosis by reading `ReviewCardView.swift`
    directly — the zoom icon really was a decorative `.overlay`, not a `Button`; the only tap gesture
    was `.onTapGesture(count: 2)` which *resets* scale rather than zooming; the `MagnificationGesture`
    really was nested inside the card's scrolling content, where the enclosing `ScrollView`'s own
    drag recognizer competes for the gesture. New `DesignSystem/ZoomableImageView.swift`: a shared
    full-screen viewer (`MagnificationGesture` for pinch, double-tap to zoom in/out, a `DragGesture`
    gated on `scale > 1` for pan, both combined via `SimultaneousGesture` so pinch-then-drag doesn't
    fight itself, bounded 1×–5×, black background, real `Button` ✕ to dismiss), presented via
    `.fullScreenCover` instead of embedded in the scrolling card — sidesteps the gesture-competition
    problem entirely rather than trying to win it. `ReviewPhoto` now opens it from either the photo
    tap or the (now-real-`Button`) zoom icon. **Also swapped `CoffeeDetailView.swift`'s
    near-identical private `FullPhotoView`** (same broken-adjacent pattern, though it was already a
    dedicated full-screen sheet so its pinch-to-zoom did work — it just couldn't pan once zoomed) for
    the same shared component, deleting the now-dead duplicate — closes the row's own "would benefit
    from the same viewer" aside for free.
  - Not locally compiled (no Xcode here). Most likely first things to check on a red compile: the
    `AttributedString.range(of:)` + `.link`/`.foregroundColor` subscript-attribute pattern in
    `InsightsView.findingAttributedText` (not used elsewhere in this codebase); the
    `SimultaneousGesture(pinchGesture, dragGesture)` composition in `ZoomableImageView`; and the
    `Group { if let ... Button ... else ... }` pattern in `DataQualityCard.row` (mirrors
    `InsightsCharts.legendRow`'s already-landed shape from `#50`, so lower risk).
  - `ios/MyCoffee/Sources/{Features/Insights/{InsightsView,InsightsCharts,InsightsFindings,
    InsightsAggregation,DataQualityCard},Features/Review/ReviewCardView,
    Features/Coffees/CoffeeDetailView,DesignSystem/ZoomableImageView}.swift`
  - Commit: `8cbeb5c` (merge) + one follow-up commit on `ios-staging` (see `git log`)

- [2026-08-14 UTC, later session] 50 Insights charts: per-label average rating + tap-to-filter — branch `ios-staging`
  - Picked up as the only `ready` `ios-ux` row (the no-op check right below this entry ran before
    Radu's `#50` landed on `origin/main`/was merged in here). Its `needs` (`#46`) was already
    `done`; the seam it flagged for ios-shell (`CoffeeStore.selectedTab`/`RootTab`) had also
    already landed the same day (`47f2934`) — confirmed by reading `Sources/Store/CoffeeStore.swift`
    directly rather than trusting the row text alone, per the integrate-before-you-start rule.
    `git branch -r --list 'origin/claude/*'` showed only this session's own branch — nothing else
    stranded to adopt.
  - **(a) Per-label average rating**: `PieSlice` (`Features/Insights/InsightsCharts.swift`) gained
    `key: FacetKey?` (`nil` only for the synthetic "Other" slice) and `averageRating: Double?`.
    `InsightsView.slices(for:facets:)` threads both straight from `FacetCounts.Entry` — no new
    computation needed, the facet layer already carries `averageRating` (same value the filter
    sheet's pills already show). Legend rows now render `Label · N · ★X.X` via a small
    `legendText(for:)` helper, omitting the `★` segment entirely when `averageRating` is `nil`
    (unrated slice) — same "missing fields omit their row" convention as everywhere else, applied
    at the segment level here. The "Other" bucket's average is a count-weighted mean over only its
    *rated* sub-entries (`weightedAverageRating`) so a pile of unrated overflow values can't drag
    it toward 0 — an overflow bucket that's, say, 80% unrated coffees at ★4.5 now still shows
    ★4.5, not ★0.9.
  - **(b) Tap-to-filter**: each legend row with a non-nil `key` is wrapped in a `Button`
    (`.buttonStyle(.plain)`, so it doesn't inherit accent-color tinting); "Other" stays plain text
    since it doesn't correspond to one filterable value. `CategoryPieChart` takes an optional
    `onSelect: ((FacetKey) -> Void)?` (nil-able so a future preview/test can render a
    non-interactive chart without wiring a handler). `InsightsView.selectInCoffees(dimension:key:)`
    builds a **fresh** `CoffeeFilter()` and calls the existing `toggleFacet(_:dimension:in:)`
    helper (already shared from `FilterSheetView.swift`) to set exactly that one value — starting
    from empty rather than layering onto whatever filter was already active, matching the row's
    "replaces the whole filter" framing (same semantics as the top filter cards' `.replacing`).
    Then sets `store.filter` and `store.selectedTab = .coffees` in one call. The Unknown slice
    works for free: `toggleFacet`'s existing `(_, .unknown)` case already flips
    `unknownDimensions`, exactly the row's own ask.
  - **One real gap found and closed, not just threaded through**: `.decaf` is one of
    `InsightsView.pieDimensions` (already rendering a pie before this row), but
    `toggleFacet`/`isFacetSelected` (`FilterSheetView.swift`) had no `(.decaf, .bool)` case — dead
    code until now, because the filter sheet always special-cases decaf as a segmented
    `DecafRow` control and never routes it through the generic per-dimension pill loop. Without
    this case, tapping the decaf legend in Insights would have silently no-opped (`default: break`
    on toggle, `default: false` on selected-check). Added both cases so decaf deep-links exactly
    like every other dimension; verified this is additive only — the filter sheet's own decaf UI
    never calls either function, so no existing behavior changes.
  - **`RootTabView.swift`**: `TabView(selection: $store.selectedTab)` + a `.tag(RootTab.*)` per
    tab, the wiring half of the seam ios-shell's row explicitly left for this lane. No other
    behavior change — `store.reviewQueueCount` badge, `.environmentObject`, and the two `.task`
    blocks are untouched.
  - Not locally compiled (no Xcode here) — if the next compile check goes red, the two most likely
    spots are `legendRow`'s `Group { if let ... { Button ... } else { content } }` pattern (not
    used elsewhere in this codebase — a local `content` view value built once and referenced from
    both branches) and the two new `(.decaf, .bool(...))` switch cases in `FilterSheetView.swift`.
  - `ios/MyCoffee/Sources/Features/{Insights/{InsightsView,InsightsCharts},Coffees/FilterSheetView,
    Root/RootTabView}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-14 UTC] No-op session. `status/BACKLOG.md` on `ios-staging`: every
  `ios-ux`-tagged row (`18/27/28/37/42/47`) is still `done`; no new `ios-ux`
  row has appeared since `#47`. The only rows touched this cycle were
  backend's `#49` (retract a stale `coffees` column on re-adjudication —
  landed and verified live) and data's `#39`/`#48(b)` — none in this lane's
  owned paths. Swept `git branch -r --list 'origin/claude/*'` — only
  `origin/claude/hopeful-johnson-mu7ff6` exists (this session's own assigned
  branch, 0 commits ahead of `main` under `Sources/Features`,
  `Sources/DesignSystem`, or `Resources`), so nothing stranded to adopt.
  Merged `origin/main` into `ios-staging` (two conflicts: `status/BACKLOG.md`
  row `#49` — HEAD's stale `ready` copy vs. `main`'s newer `done` writeup,
  kept `main`'s; `status/backend.md` — HEAD's side was empty at that spot,
  `main` had the full `#49` session writeup, kept it whole). Stopping cleanly
  per the lane's documented no-op behaviour; no feature code changed.

- [2026-08-13 UTC, later session] No-op session. `status/BACKLOG.md`: every
  `ios-ux`-tagged row (`#18/#27/#28/#37/#42/#47`) is `done`; the only `ready`
  rows (`#29`/`#39`/`#48`) are all `data`-lane. Merged `origin/main` into
  `ios-staging` (clean, no conflicts — picked up backend/publish status-note
  additions, no code). Swept `git branch -r --list 'origin/claude/*'` (87
  branches, up from prior sweeps) via `git rev-list --count
  ios-staging..origin/<branch> -- ios/MyCoffee/Sources/Features
  ios/MyCoffee/Sources/DesignSystem ios/MyCoffee/Resources` — 51 non-zero
  hits, a much larger set than any prior sweep. Spot-checked a representative
  sample across every distinct branch-name family (`determined-thompson-*`,
  `confident-cerf-*`, `peaceful-mccarthy-*`, `hopeful-johnson-*`,
  `wizardly-thompson-*`, `relaxed-thompson-*`) with `git diff --stat`: every
  one is a **net-negative diff** against current `ios-staging` (e.g. "140
  insertions, 3069 deletions"), including deleting `Features/WhatsNew/
  WhatsNewView.swift` — i.e. every one of these branches forked *before* the
  current state (pre-#47, several pre-#37/#42) and has nothing to contribute;
  same "stale pre-current fork" shape every prior sweep in this file has
  already documented, just at higher branch count. Nothing stranded to adopt.
  Stopping cleanly per the lane's documented no-op behaviour; no feature code
  changed.

- [2026-08-13 UTC] No-op session. `status/BACKLOG.md` on `ios-staging`: every
  `ios-ux`-tagged row is `done` (`18/27/28/37/42/47`) — `#37`/`#42`/`#47` were
  already landed in prior sessions and merely stale on `main`'s copy of the
  file, same divergence pattern the 2026-08-12 sessions below already caught.
  The only `ready` rows in the whole table are `#39`/`#48`, both `data`-lane
  (`normalize.js`/vocab-owned) — none `ios-ux`. Swept `git branch -r --list
  'origin/claude/*'` — only this session's own branch, touching nothing under
  `Sources/Features`/`Sources/DesignSystem`/`Resources`, so nothing stranded to
  adopt. Merged `origin/main` into `ios-staging` (one conflict, in
  `status/backend.md` — two backend session-note entries appended at the same
  spot on divergent history, same recurring pattern; resolved as a union, kept
  both entries, no code involved). Stopping cleanly per the lane's documented
  no-op behaviour; no code changes this session.

- [2026-08-12 UTC, later session] `#47` (What's New screen) picked up — `#45`
  (backend) and `#46` (ios-shell) are both `done` on `origin/main`/`ios-staging`
  now, unblocking it. Before writing anything, swept `git branch -r --list
  'origin/claude/*'` — only this session's own branch exists, touching nothing
  under `Sources/Features`/`Sources/DesignSystem`/`Resources`, so nothing
  stranded to adopt. **Also caught a stale plan going in**: this session
  initially drafted its own client-only fix for `#37`
  ("Needs review" reflects only actionable items) against `status/BACKLOG.md`
  as checked out on `main`, which still showed `#37` `ready` — merging
  `origin/main` into `ios-staging` immediately surfaced that `#37` was already
  `done` on `ios-staging` (`57f6073`, a fuller fix via
  `Features/Review/ReviewFeedCache.swift` that also gates the Review tab badge,
  not just the detail-page button). Discarded the draft before committing
  anything, per the "integrate before you start" rule — this is exactly the
  failure mode `CLAUDE.md` §12 warns about, caught before it produced a
  duplicate. See `## Done` below for the `#47` work actually landed this
  session.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-12 UTC] Closed the batch-edit atomicity gap the ios-shell lane's
  2026-08-12 session flagged (`status/ios-shell.md`): it added
  `CoffeeStore.editFields`/`APIClient.editCoffeeFields` and asked UX to swap
  the call site, since the fix only takes effect once the sheet stops calling
  the single-field path in a loop. No numbered `BACKLOG.md` row was actually
  `ready` for this lane this cycle — `#37` and `#42` were already `done` on
  `ios-staging` before this session started (`57f6073` / `be0b40a`); `main`'s
  copy of `status/BACKLOG.md` still showed stale rows because the dev/ship
  split means `ios-staging` never pushes there until Publish merges. `#47`
  (What's New screen) stays `blocked` — `#45`/`#46` aren't done yet.
  - Merged `origin/main` into `ios-staging` first (two real conflicts in
    `status/BACKLOG.md`, reconciled by keeping `ios-staging`'s newer #41/#42
    rows and `main`'s newer #43/#44/#45/#46/#47/#48/#39 rows; two trivial Swift
    conflicts — a dead unused `pendingReviewCount` left over from an earlier
    #37 draft in `RootTabView.swift`, and `ReviewQueueView.swift`'s older
    fire-and-forget resolve path superseded by the outbox-backed one — both
    resolved by keeping `ios-staging`'s side, no logic change).
  - `Features/Coffees/CoffeeEditSheet.swift`'s `save()` built a
    `[(field, value)]` tuple array and called `store.editField` once per entry
    in a loop — exactly the gap ios-shell's write-up named. Changed the
    array's element type to the shared `CoffeeFieldEdit` struct (already
    public from #41) and, at the end of `save()`, call
    `store.editFields(coffeeId:edits:)` when more than one field changed,
    falling back to the existing single-field `store.editField` when exactly
    one did. No behavior change for a single-field save; a multi-field save
    (e.g. changing `roaster` and `roasterCountry` in the same sheet visit) now
    goes over the wire as one request instead of two racing ones.
  - Not locally compiled (no Xcode here) — a narrow, mechanical call-site
    change against an existing, already-used type, so a red compile check
    here would most likely be a typo, not a design gap.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-11 UTC] No-op session. `BACKLOG.md`: all five `ios-ux` rows (#18,
  #27, #28, #37, #42) are `done`. The only `ready` rows this cycle are `#39`
  (data, altitude/weight/rating sanity envelopes), `#43`/`#44` (backend,
  photo-size budget + auto-create-farms) — none in this lane's owned paths.
  Checked `git branch -r --list 'origin/claude/*'` — only this session's own
  branch (`origin/claude/hopeful-johnson-984get`, exactly `origin/main`'s tip)
  exists; nothing stranded touching `Sources/Features`, `Sources/DesignSystem`,
  or `Resources` to adopt.
  Merged `origin/main` into `ios-staging` (two conflicts, both pure status-note
  divergence, no code): `status/BACKLOG.md` had `main`'s stale `ready`/`blocked`
  for `#41`/`#42` (ios-staging already shipped both `done`) plus main's new
  `#39`/`#44`/`#43` rows — kept `ios-staging`'s `done` status for `#41`/`#42`
  and folded in the three new rows; also fixed a pre-existing formatting bug
  in `main`'s copy where row `#43`'s text ran on into row `#39`'s "Radu: accept
  all guesses..." sentence with no row break — restored `#43` as its own row,
  ending at "Measure a display's bytes before/after". `status/backend.md` had
  two backend session-note blocks appended at the same spot on divergent
  history (same pattern as prior sessions' merges) — resolved as a union, kept
  both. Also picked up main's 50 MB budget work (`ImageStore.swift` 30 MB cap +
  `MyCoffeeApp.swift` launch eviction, `CLAUDE.md` §12) cleanly, no conflict —
  both shell/root-owned, untouched here. Stopping cleanly per the lane's
  documented no-op behaviour; no feature code changed.

- [2026-08-10 UTC] No-op session (second check same day). `BACKLOG.md`: still
  only four `ios-ux` rows (#18, #27, #28, #37), all `done`. The lone `ready`
  row is `#39` (data lane, altitude/weight/rating sanity envelopes in
  `normalize.js`) — not ours. `#26` stays `human` (still awaiting Radu's
  accuracy verdict) and `#29` stays `data`/`blocked` on it. Fetched and merged
  `origin/main` (`310b49b`, backend's own session-check commit on top of
  `#39`'s plan-doc addition and the process/decaf tag fix) into `ios-staging`
  — merge was clean (one auto-merge each in `BACKLOG.md`/`status/backend.md`,
  pure status-note unions) and the resulting tree is byte-identical to
  `origin/ios-staging`'s, so this is bookkeeping only, no code changed.
  Checked `git branch -r --list 'origin/claude/*'` — only this session's own
  branch exists and it touches none of `Sources/Features`,
  `Sources/DesignSystem`, or `Resources`, so nothing stranded to adopt.
  Pushed the merge (`89f38d0`) to `ios-staging`. Stopping cleanly per the
  lane's documented no-op behaviour.

- [2026-08-10 UTC] No-op session. `BACKLOG.md`: all four `ios-ux` rows (#18,
  #27, #28, #37) are still `done`; `#29` (the only other row touching
  anything downstream of this lane) is `data`-owned and `blocked` on `#26`
  (still `human`, awaiting Radu's accuracy verdict) — nothing newly `ready`
  for `ios-ux`. `origin/main`'s tip (`692c16b`, data lane `#38` — roaster
  countries) is already an ancestor of `ios-staging` HEAD via the prior
  session's merge (`git merge origin/main` reported "Already up to date").
  Checked `git branch -r --list 'origin/claude/*'` — only this session's own
  branch exists, and it touches none of `Sources/Features`,
  `Sources/DesignSystem`, or `Resources`, so nothing stranded to adopt.
  Stopping cleanly per the lane's documented no-op behaviour; no feature
  code changed.

- [2026-08-09 UTC] No-op session (second check same day). `BACKLOG.md`: all
  four `ios-ux` rows (#18, #27, #28, #37) still `done`; the only `ready` row
  is `#38` (data lane). `origin/main` (`b466788`) is already an ancestor of
  `ios-staging` HEAD (`501a587`), confirmed via `git merge-base
  --is-ancestor` — no new merge needed, the prior session's reconciliation
  already covers it. Briefly drafted a client-only fix for `#37` before
  checking branch state and discovering it was already shipped in `57f6073`
  with a more complete `ReviewFeedCache`-based approach (also gates the
  Review tab badge, which a per-view fetch wouldn't have) — discarded the
  draft rather than duplicate it. Stopping cleanly per the lane's documented
  no-op behaviour; no feature code changed.

- [2026-08-09 UTC] No-op session. `BACKLOG.md`: all four `ios-ux` rows (#18,
  #27, #28, #37) are `done`. Confirmed by reading `origin/ios-staging`'s copy
  of `BACKLOG.md` directly (not just this file's own `## Done` section) —
  `#37` landed in `57f6073` (2026-08-08, prior session) but `origin/main`'s
  copy of `BACKLOG.md` still showed it `ready` (main hasn't had `ios-staging`
  merged into it since). Merging `origin/main` into `ios-staging` surfaced
  that exact conflict on the `#37` row (`done` vs `ready`) plus main's new
  `#38` (data lane) addition — resolved keeping `ios-staging`'s `done` for
  `#37` (it's real, verified against the landed code, not a stale claim) and
  keeping main's new `#38` row (not ours; data lane). Swept `git branch -r
  --list 'origin/claude/*'` — only this session's own branch remains, and it
  touches none of `Sources/Features`, `Sources/DesignSystem`, or `Resources`
  (`git rev-list --count` = 0), so nothing stranded to adopt. Stopping
  cleanly per the lane's documented no-op behaviour; no feature code changed.

- [2026-08-08 UTC] No-op session. `BACKLOG.md`: still only `#18`/`#27`/`#28`
  tagged `ios-ux`, all `done`. New row `#37` ("Needs review" reflects only
  actionable items, PLAN.md §11) is `ios-ux` but `blocked` on `#35`/`#36`
  (both backend, both `ready` — not done yet), so nothing to pick up; correct
  no-op per the work loop's own instructions. Merged `origin/main`
  (`aaacc88`, the accept-by-default policy doc + farm-accept + review-
  affordance backend/iOS fixes) into `ios-staging` — clean, no conflicts
  with `Features/`/`DesignSystem/`/`Resources/`. Swept
  `git branch -r --list 'origin/claude/*'` (65 branches) for stranded work
  touching `Sources/{Features,DesignSystem}/**` or `Resources/**`: several
  non-zero hits (`determined-thompson-{3tonjx,4281b1,nto1g8,x99e3x}`,
  `lanes-status-blockers-wws2lc`, `wizardly-thompson-eurlj6`,
  `new-app-infrastructure-setup-h3r3wz`), all pre-`#18` scaffolding/design-
  system commits already superseded by the landed `#18`/`#27`/`#28` work
  (same commit SHAs as `ios-staging`'s own history in most cases) — nothing
  to adopt. Stopping cleanly; no code changes this session.

- [2026-08-07 UTC, later same day] No open `BACKLOG.md` row (`#18`/`#27`/`#28`
  still the only `ios-ux` rows, all `done`; `#29` still `human`-gated on `#26`).
  Found real work anyway: `origin/main` had moved to `da12d12` ("iOS: listing
  photos, review scroll/back fixes, coffee-page cleanups") — another off-lane
  push straight to `main` touching both `ios-ux`-owned files
  (`Features/Coffees/CoffeeDetailView.swift`, `Features/Review/{ReviewCardView,
  ReviewQueueView}.swift`, new `Features/Review/CoffeeReviewSheet.swift`) and
  `ios-shell`-owned ones (`API/Wire/{CoffeeMapping,SnapshotWire}.swift`,
  `Store/SyncEngine.swift`) — same "commits to `main` instead of `ios-staging`"
  footgun `CLAUDE.md` §12 already documents, not this lane's mistake to fix by
  policy but stranded work to integrate per `status/README.md`'s rule.
  - `git merge origin/main` into `ios-staging`: one real conflict, in
    `Features/Review/ReviewQueueView.swift` — `ios-staging`'s side only
    differed in a doc comment (its actual body/load()/toolbar code was already
    identical to `origin/main`'s pre-`da12d12` state, since this lane's own
    `4e491be`/shell's `ef50a07` had already landed equivalently on both
    branches before `da12d12` forked). Resolved by taking `origin/main`'s side
    (the new shared `ReviewCardStack` component `da12d12` extracted, which the
    rest of the already-auto-merged file now references) — no functional
    HEAD-only content was dropped. Pushed the merge to `ios-staging`
    (`9b9fc95`).
  - **One real regression caught and fixed, not just merged through**: the new
    `CoffeeReviewSheet.swift` (per-coffee review sheet, launched from the
    detail page's "needs review" marker) was written by the `da12d12` session
    against a fork that predated this lane's own outbox-durability fix — its
    `load()` called `client.resolveReview(id:value:)`/`client.dismissReview(id:)`
    directly on `APIClient`, the exact fire-and-forget pattern already fixed in
    `ReviewQueueView.swift` (see the 2026-08-06 entry below). Swapped both for
    `store.resolveReview(taskId:value:)`/`store.dismissReview(taskId:)` on the
    `CoffeeStore` (added `@EnvironmentObject private var store: CoffeeStore`,
    same as `ReviewQueueView`) so per-coffee resolutions from the detail page
    also survive offline/app restart through `MutationOutbox`, not just the
    Review tab's. `client` stays for `reviewFeed()` (the GET, unaffected).
  - Also swept `git branch -r --list 'origin/claude/*'` (still 57) — no new
    candidates beyond the one dismissed in the entry below (`hopeful-johnson-
    icvqmr`, a stale pre-durable-outbox fork, correctly not adopted).
  - Not locally compiled (no Xcode here) — if the next compile check goes red,
    check `CoffeeReviewSheet.swift`'s new `@EnvironmentObject` line first (it's
    a one-line addition to an otherwise `da12d12`-authored file) and the
    resolved `ReviewQueueView.swift` conflict region (lines ~1–90, the new
    `ReviewCardStack` struct).
  - `ios/MyCoffee/Sources/Features/Review/{CoffeeReviewSheet,ReviewQueueView}.swift`
  - Commit: `9b9fc95` (merge) + one follow-up commit on `ios-staging` (see
    `git log`)

- [2026-08-07 UTC] No-op session. `BACKLOG.md`: only `ios-ux` rows are `#18`,
  `#27`, `#28` — all `done`, unchanged. The two seam gaps this lane had open
  (review durability, Insights "This month" brief) are also closed as of
  yesterday's session (`4e491be`) — confirmed by reading `ReviewQueueView.swift`
  and `InsightsView.swift` on `origin/ios-staging`: both call through
  `CoffeeStore` (`resolveReview`/`dismissReview`/`loadBrief`), no direct
  `APIClient` mutation calls left in UX-owned files. `#29` (data, phase 6)
  stays `blocked` on `#26`, which is still `human` — not this lane's row
  either way.
  Full-fetched all `origin/claude/*` branches (57, up from 56) and swept every
  one via `git rev-list --count origin/ios-staging..<branch> --
  ios/MyCoffee/Sources/Features ios/MyCoffee/Sources/DesignSystem
  ios/MyCoffee/Resources`. Seven non-zero hits, all inspected by tree diff, none
  stranded to adopt:
  - `coffee-app-plan-9jdh0c`, `new-app-infrastructure-setup-h3r3wz`,
    `mycoffee-publish-autopilot-rv8cve`, `relaxed-thompson-ceai5p`: pure
    deletions against current `ios-staging` (pre-#27/#28 forks, same shape
    every prior sweep has found).
  - `modest-newton-oxaddt`: identical diff to the above (also a stale
    pre-#27/#28 fork).
  - `wizardly-thompson-0g9i90`: already inspected and dismissed by
    `status/ios-shell.md`'s 2026-08-05 sweep (pre-`roasterId`-fix snapshot).
  - `hopeful-johnson-icvqmr`: the one real candidate — flagged for the record
    by backend's 2026-08-06 sweep as "not integrated." Diffed it directly
    against `origin/ios-staging`: it wires the same "This month" brief
    (renaming `BriefCard`→`EditorialBriefCard`) but its `ReviewQueueView.swift`
    still calls `client.resolveReview`/`client.dismissReview` directly —
    it forked from `ef50a07` *before* this lane's own `4e491be` added the
    durable `CoffeeStore.resolveReview`/`.dismissReview` wiring. Adopting it
    would be a **regression** (reintroducing fire-and-forget mutations over
    the already-landed durable outbox path), not an integration. Not adopted;
    its brief-card naming (`EditorialBriefCard` vs. the landed `BriefCard`) is
    a cosmetic difference not worth cherry-picking alone.
  No code changes this session — stopping cleanly per the work loop (do not
  invent work).

- [2026-08-06 UTC, ios-ux lane] Closed two cross-lane seam gaps the shell
  lane's `ef50a07` landed today, both explicitly flagged in that commit "for
  the UX lane to call" — no open `BACKLOG.md` row (#18/#27/#28 all `done`),
  same precedent as the 2026-08-02 UX-wiring-gap entry below.
  - **`Features/Review/ReviewQueueView.swift`**: swapped the direct
    `client.resolveReview(id:value:)`/`client.dismissReview(id:)` calls in
    `load()`'s `engine.onAccept`/`.onDismiss` hooks for
    `store.resolveReview(taskId:value:)`/`store.dismissReview(taskId:)` on the
    `CoffeeStore` already available via `.environmentObject` (`RootTabView`).
    Accepts/dismisses now persist through `MutationOutbox` — durable across
    offline/app restart — instead of a fire-and-forget network call that
    silently dropped on failure. `client.reviewFeed()` (the GET, unaffected)
    stays as-is; only the two mutating calls moved.
  - **`Features/Insights/{InsightsView,BriefCard}.swift`**: added the
    editorial "This month" section PLAN.md §6.4 asks for, reusing
    `GET /api/brief` via the new `CoffeeStore.loadBrief()`. New
    `BriefCard.swift` (title + body, omitted entirely when `nil` — same
    "missing fields omit their row, never N/A" convention as `DataQualityCard`
    right above it), fetched in a `.task` on `InsightsView`'s `NavigationStack`
    and placed between the Data quality card and the findings section. New
    `Symbols.brief = "newspaper"` in `DesignSystem/Symbols.swift`.
  - **Not wired, flagged rather than guessed**: the shell lane's same
    `ef50a07`-era work also added `APIClient.createReviewRule(kind:
    canonicalId:alias:)` (`POST /api/review/rules`), but `ReviewQueueEngine`'s
    long-press/"Accept all" rule creation only has a display-string
    `ReviewCandidate.value` to work with — no canonical vocabulary `Int` id
    anywhere in ux-owned models — so there's no way to call it durably without
    guessing at an id lookup that doesn't exist yet. `ReviewRule` stays a
    client-side-only convenience for this session, same as before.
  - Not locally compiled (no Xcode here) — if the next compile check goes red,
    check `ReviewQueueView.swift`'s new `@EnvironmentObject` (unused `client`
    var is still needed for `reviewFeed()`, just not for the two mutations
    anymore) and `BriefCard.swift`'s `if let brief` self-conditional body.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-05 UTC] No-op session. `BACKLOG.md`: only `ios-ux` rows are `#18`,
  `#27`, `#28` — all `done`, unchanged from the prior check. The two flagged
  seam gaps from `#27`/`#28` (shell adding `CoffeeStore.loadBrief()` for
  Insights' "This month" section, and an `APIClient`/`CoffeeStore` surface
  for `GET /api/review` / `POST /api/review/:id` / `POST /api/review/rules`
  so the review queue can round-trip through `MutationOutbox`) are still
  unclaimed — confirmed via `grep` for `loadBrief`/review-route methods in
  `Sources/Store` and `Sources/API`: none exist yet. `status/ios-shell.md`'s
  latest entries (2026-08-04) merged `origin/main` but added no new
  `ios-shell`-owned code either. Swept `git branch -r --list 'origin/claude/*'`
  via `git rev-list --count origin/ios-staging..<branch> -- ios/MyCoffee/Sources/Features
  ios/MyCoffee/Sources/DesignSystem ios/MyCoffee/Resources`: the two
  non-trivial hits (`claude/coffee-app-plan-9jdh0c`,
  `claude/new-app-infrastructure-setup-h3r3wz`) both diff as pure deletions
  against current `ios-staging` — they predate the #18/#27/#28 work and carry
  nothing to adopt. Merged `origin/main` into `ios-staging` (clean — picked up
  backend's `FlexibleDecoding`/`SnapshotWire`/`Vocab.swift` nullable-`isoCode`
  fix and a `CoffeeDetailView.swift` follow-up, both shell-owned, no conflicts
  with UX-owned paths). Stopping cleanly per the lane's documented no-op
  behaviour; no code changes this session.

- [2026-08-04 UTC] No-op session. `BACKLOG.md`: only `ios-ux` rows are `#18`,
  `#27`, `#28` — all `done`. The two flagged seam gaps from `#27`/`#28`
  (shell adding `CoffeeStore.loadBrief()` for the Insights "This month"
  section, and `APIClient`/`CoffeeStore` methods for `GET /api/review` /
  `POST /api/review/:id` / `POST /api/review/rules` so the review queue can
  round-trip through `MutationOutbox` instead of only mutating local state)
  are still unclaimed — confirmed via `status/ios-shell.md`'s own 2026-08-04
  entry, which merged `main` but added no new `ios-shell`-owned code. Swept
  `git branch -r --list 'origin/claude/*'` — only this session's own branch
  (`claude/hopeful-johnson-0fzb9o`) exists, 0 commits ahead of `ios-staging`
  in any owned path, nothing stranded to adopt. `git merge origin/main` into
  `ios-staging` was already up to date (no divergence to reconcile). Stopping
  cleanly per the lane's documented no-op behaviour; no code changes this
  session.

- [2026-08-03 UTC] No-op session (second cycle same day). `BACKLOG.md`: `#27`
  (needs 22, 24) still `blocked` — `#24` unchanged, still blocked on `#23`
  (Vertex extension). `#28` (needs 22) stays `done`. Re-swept `git branch -r
  --list 'origin/claude/*'` (now 32 branches) via `git rev-list --count
  ios-staging..origin/<branch> -- ios/MyCoffee/Sources/Features
  ios/MyCoffee/Sources/DesignSystem ios/MyCoffee/Resources` — zero for every
  branch, nothing stranded to adopt. Merged `origin/main` into `ios-staging`
  (clean, only `status/backend.md` session notes, no code). Stopping cleanly
  per the lane's documented no-op behaviour; no code changes this session.

- [2026-08-03 UTC] No-op session. `BACKLOG.md`: `#27` (needs 22, 24) still
  `blocked` — backend's own 2026-08-03 session check confirms `#23`/`#24`
  remain `blocked` on purpose (the on-Mac 20-photo verification gate, PLAN.md
  §8, still hasn't run; no Mac in any sandbox). `#28` (needs 22) stays `done`
  (2026-08-01 session). Swept `git branch -r --list 'origin/claude/*'` (now
  ~19 branches) via `git rev-list --count origin/ios-staging..origin/<branch>
  -- ios/MyCoffee/Sources/Features ios/MyCoffee/Sources/DesignSystem
  ios/MyCoffee/Resources` — zero for every branch, nothing stranded to adopt.
  Merged `origin/main` into `ios-staging` (one conflict, in
  `status/backend.md` — two backend session-note entries appended at the same
  spot on divergent history, same pattern as the 2026-08-02 merge; resolved
  as a union, kept both entries, no code involved). Stopping cleanly per the
  lane's documented no-op behaviour; no code changes this session.

- [2026-08-02 UTC] No-op session. `BACKLOG.md`: `#27` (needs 22, 24) still
  `blocked` — backend's `#24` hasn't landed. `#28` (needs 22) is already `done`
  (prior session). Swept `git branch -r --list 'origin/claude/*'` for stranded
  work touching `Sources/{Features,DesignSystem}/**` or `Resources/**`
  (`git log origin/ios-staging..origin/<branch> -- ios/MyCoffee/Sources/Features
  ios/MyCoffee/Sources/DesignSystem ios/MyCoffee/Resources` across all 24
  branches) — none touch either path, nothing to adopt. Merged `origin/main`
  into `ios-staging` (one conflict, in `status/backend.md` — two backend
  session-note entries appended at the same spot on divergent history; resolved
  as a union, kept both entries, no code involved). Stopping cleanly per the
  lane's documented no-op behaviour; no code changes this session.

- [2026-08-01 UTC] No-op session. Checked `status/BACKLOG.md`: no `ios-ux` row is
  `ready` — `#27` (needs 22, 24) and `#28` (needs 22) are both still `blocked`.
  Backend landed `#21` on `main` this cycle (migrations 008–009 + `routes/coffees.js`)
  and flipped `#22` (ios-shell) `blocked`→`ready`, but that's the shell lane's row, not
  ours — `#27`/`#28` still need `#22` actually done (and `#27` also needs `#24`,
  untouched). Checked `git branch -r --list 'origin/claude/*'` for stranded prior work
  touching `Sources/{Features,DesignSystem}/**` or `Resources/**` per the "integrate
  before you start" rule — none of the 15 open `claude/*` branches touch either path
  (`git log origin/ios-staging..origin/<branch> -- ios/MyCoffee/Sources/Features
  ios/MyCoffee/Sources/DesignSystem` empty for all of them), so nothing to adopt.
  Merged `origin/main` into `ios-staging` (clean, no conflicts with
  `Features/`/`DesignSystem/`/`Resources/` — picked up backend's #14/#21 landing) and
  stopping cleanly, per the lane's documented no-op behaviour.

- [2026-07-31 UTC] No-op session. Checked `status/BACKLOG.md`: no `ios-ux` row is
  `ready` — `#27` (needs 22, 24) and `#28` (needs 22) are both still `blocked` on
  the shell lane's `#22` (Remote repository + SyncEngine), which is itself blocked
  on backend `#21`. Checked `git branch -r --list 'origin/claude/*'` per the
  "integrate before you start" rule — only this session's own branch, nothing
  stranded to adopt. Fast-forwarded `ios-staging` to `origin/main` (picked up the
  data-lane #12/#13/#34 consolidation + backend #11 migrations, no conflicts with
  `Features/`/`DesignSystem/`/`Resources/`) and stopping cleanly, per the lane's
  documented no-op behaviour.

## Done

- [2026-08-12 12:00 UTC] 47 What's New screen — branch `ios-staging`
  - `Features/WhatsNew/WhatsNewView.swift` (new): segmented Live/Plan control
    (`Picker(.segmented)`) over `GET /api/whatsnew` (#46's
    `APIClient.whatsNew()` → `WhatsNewResponseDTO`). Live renders a plain
    `List` of feature cards (title + one-line detail + an area chip, shown
    only when `item.area` is non-nil per the DTO's own contract that `area`
    is live-only); Plan renders `Section("Needs your approval")` pinned first,
    then one `Section` per lane in a fixed Backend/Data/iOS order (not
    alphabetical over `byLane`'s keys — a stable, product-meaningful order),
    skipping any lane section that's empty. Read-only, no actions, per the
    row's "v1" scope. `ContentUnavailableView` for the load-failed and
    genuinely-empty cases (with "Try again" on the failure path), matching the
    pattern already used in `CoffeeReviewSheet`/`ReviewQueueView`.
  - `Features/Coffees/SettingsSheet.swift`: added a "What's New" row
    (`NavigationLink` → `WhatsNewView()`) above the existing Disconnect
    section — reached from Settings, not a 4th tab, per the row's own spec.
  - `DesignSystem/Symbols.swift`: three new entries under "What's New (#47)"
    (`whatsNew` for the Settings row icon, `whatsNewEmpty`, `whatsNewUnavailable`).
  - Uses `@EnvironmentObject private var config: AppConfig` +
    `try APIClient(config: config)`, the same pattern `SettingsSheet.swift`
    already uses for its own status check — no new shell/API surface needed,
    `#46` already published everything this screen consumes.
  - Not locally compiled (no Xcode here) — flag the compile lane to
    `Features/WhatsNew/WhatsNewView.swift`, the `SettingsSheet.swift` diff, and
    the three new `Symbols.swift` entries specifically if the next compile
    check goes red.
  - No `BACKLOG.md` row lists `47` as a `needs` dependency, so nothing to
    unblock.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-11 UTC] 42 Edit sheet with consistency dropdowns (PLAN.md §12) — branch `ios-staging`
  - Merged `origin/main` into `ios-staging` first per the integrate-before-you-start rule: `git branch -r --list
    'origin/claude/*'` showed nothing stranded touching `Sources/{Features,DesignSystem}` or `Resources`, but the merge
    itself surfaced that `#41` (ios-shell) had already landed on `ios-staging` (`5b76a6c`, flipping `#42`→`ready`)
    while `main`'s own copy of `status/BACKLOG.md` still showed `#41` merely `ready`/`#42` `blocked` — resolved the
    conflict by keeping `ios-staging`'s more current rows (same "each branch only knows its own lane's latest" gap
    the shell lane's own 2026-08-10 entry documents). `#37` turned out to be done too (`57f6073`, already on
    `ios-staging`) — the copy of `status/ios-ux.md` this session read at the very start (before the merge) was stale
    and didn't show it; not redone.
  - New `Sources/Features/Coffees/CoffeeEditSheet.swift`. A pencil `ToolbarItem` on `CoffeeDetailView` (next to the
    existing Share button) opens it as a sheet.
  - **Every vocab-backed field is a picker, never free text** (the row's own requirement, so an edit can't spawn an
    inconsistent variant): origin country is a multi-select searchable list over `vocabulary.countries` filtered
    `isOrigin` (no "is this a blend" toggle — `isBlend` is derived server-side from how many ids resolve, same as
    extraction); roaster country is a single-select over `isRoaster` countries; roaster and farm are single-select
    searchable lists over their vocab tables **plus** an "Add new…" `TextField` + `Use` button (mirrors
    `ReviewCardView`'s existing "Other…" reveal pattern exactly) that routes through #40's get-or-create. Countries
    have no add-new section at all (`VocabPickerView`'s `newValue: Binding<String>?` is `nil` for the two country
    pickers) — #36 only get-or-creates roasters/farms, countries stay closed.
  - **Process** is a `Picker` over `Profile.allCases` + a literal "Unknown" case tagged `Profile?.none` (the standard
    optional-selection `Picker` pattern — tags and the binding must be the exact same `Profile?` type for SwiftUI's
    tag-matching to work, not just compile), with `isDecaf` as a separate `Toggle` (decaf is orthogonal to process,
    matching pushback #3 / `DecafBadge`'s own precedent).
  - **Raw-value formatting sent to `CoffeeStore.editField`**, reverse-engineered from `backend/src/lib/normalize.js`'s
    parsers rather than guessed (checked every regex): altitude → `"<min> m"` or `"<min>-<max> m"` (matches
    `ALTITUDE_RANGE_RE`/`_SINGLE_RE`); weight → `"<grams>g"` (`WEIGHT_RE`); price → `"<amount> EUR"` (the
    `€|eur\b` branch of `CURRENCY_PATTERNS`, confidence 1.0 — editing intentionally targets the EUR column directly
    rather than round-tripping through an original-currency+FX pair); rating → `"<value>/5"` (the highest-confidence
    `parseRating` branch, not the bare-number fallback); roasted-on → plain `PlainDate.isoString` (`YYYY-MM-DD`, the
    ISO branch of `parseDate`); origin country → selected names joined with `", "` (`resolveOriginCountries`'s
    `MULTI_VALUE_SPLIT_RE` includes comma); roaster/farm/roaster-country → the bare canonical name string;
    profile → `"<displayName>"` + `" decaf"` when the toggle is on, or bare `""` when Unknown+not-decaf is explicitly
    chosen (`canonicalize('profile', ...)` never returns `null` for a non-null string, even empty, so this
    legitimately clears a coffee to Unknown rather than 422ing).
  - **Only actually-changed fields round-trip** — every draft `@State` is diffed against a `private let original*`
    snapshot captured in `init` from the `Coffee` the sheet opened with (not against "is the field empty", which
    would have been wrong: the rating `Slider` and roasted-on `DatePicker` both need a concrete non-nil default to
    render at all, so an untouched optional field defaulting to e.g. 3.0★ must never look "changed"). Solved with a
    `hasRating`/`hasRoastedOn` pair of toggles mirroring each other (gate whether the control renders at all AND
    whether save even considers that field), and a small epsilon (`> 0.001` rating, `> 0.005` price) instead of exact
    `Double` equality so a value round-tripped through display formatting (`"%.2f"`) can't spuriously "change" on
    floating-point noise alone.
  - **One real Swift-correctness fix caught before it shipped, not by compiling** (no local Xcode): comparing a
    non-optional `Int`/`PlainDate` against an `Int?`/`PlainDate?` with `!=` does not compile in Swift without explicit
    wrapping — `Optional(minValue) != originalAltitudeMin`, not `minValue != originalAltitudeMin`. Caught by reasoning
    through the standard library's actual overload set rather than assuming C-style implicit promotion; fixed all
    four instances (altitude min/max, weight, roasted-on) before this file was written up as done.
  - **Also swapped `[(id: Int, name: String)]` tuples for a small `private struct VocabEntry: Identifiable, Hashable`**
    in `VocabPickerView` — tuple-label keypaths (`ForEach(_, id: \.id)` over an anonymous tuple type) are the kind of
    thing that's fine in some Swift versions and not others, and there's no local Xcode to confirm which; a named
    `Identifiable` struct removes the ambiguity entirely rather than betting on it.
  - **Flagged, not built, since it needs shell-owned files**: the backend already supports a batch `{edits:[...]}`
    request (#40) specifically so e.g. editing `roaster` and `roasterCountry` together doesn't have the derived value
    overwrite the explicit one depending on request order — but `APIClient.editCoffeeField`/`CoffeeStore.editField`
    (#41) only expose a single-field call, so this sheet fires one HTTP request per changed field with no ordering
    guarantee between them. Low-probability in practice (a user changing both roaster and roaster-country by hand in
    one save is rare), but real. **Shell lane, if you'd like to close it:** an `APIClient.editCoffeeFields(publicId:
    edits:)` + a matching `CoffeeStore` batch wrapper would let this sheet send one request instead of N; claim in
    both lane files per the seam rule if picked up.
  - Not locally compiled (no Xcode here) — if the next compile check goes red, check `CoffeeEditSheet.swift` first;
    the `Profile?`-tagged `Picker` and the four `Optional(...)` comparisons above are the most likely first things to
    check, everything else mirrors an existing pattern in `FilterSheetView`/`ReviewCardView`/`FacetFullListView`.
  - `ios/MyCoffee/Sources/{Features/Coffees/CoffeeEditSheet,Features/Coffees/CoffeeDetailView,
    DesignSystem/Symbols}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-08 UTC, later session] 37 "Needs review" reflects only actionable items — branch `ios-staging`
  - Picked up as the only `ready` `ios-ux` row after merging `origin/main` into `ios-staging`
    (backend's `#35`/`#36` landed and flipped this row `blocked`→`ready`, per `status/BACKLOG.md`).
  - Root cause confirmed by reading `backend/src/routes/review.js`: `GET /api/review` already
    filters `review_items` to `FIELD_TO_CLIENT`'s eight keys server-side (`WHERE ... field =
    ANY($clientFields)`), so the real feed never contained the non-actionable `desc_*` splits in
    the first place. The bug was purely client-side: the detail-page Review button and the Review
    tab badge both gate on `Coffee.reviewState`/`hasOpenReview` — a coarse column that lights up
    for *any* open `review_items` row, including the ones the feed itself already excludes. That
    mismatch is exactly PLAN.md §11 #37's "empty All set sheet" bug, and the same root cause was
    quietly inflating the tab badge too (not called out in the issue text, but same fix, same
    files, so folded in here rather than left half-done).
  - **New `Sources/Features/Review/ReviewFeedCache.swift`** — a small `@MainActor` shared cache
    of `coffeeId`s that have at least one client-reviewable open item, sourced from the same
    `GET /api/review` feed `ReviewQueueView`/`CoffeeReviewSheet` already fetch (`adopt(_:)` lets
    them hand it their result instead of a second network round-trip; `ensureLoaded()`/`refresh()`
    are for call sites — `CoffeeDetailView`, `RootTabView` — that don't otherwise fetch the feed).
  - **Deliberately fails open, not closed**: `reviewableCoffeeIds` stays `nil` (→
    `hasReviewableTasks` returns `true`, i.e. don't suppress) until a feed fetch actually
    succeeds. A sample/demo run with no backend configured (`APIClient.APIError.notConfigured`)
    or a transient network error never gets a positive answer, so it never wrongly *hides* a
    real affordance — it just falls back to today's coarse `hasOpenReview` behavior. This was the
    main risk in gating on network data at all, given the work loop's own "build against
    `BundledSampleRepository`, zero backend dependency" instruction — verified by reading through
    the fallback path rather than running it (no local Xcode).
  - `CoffeeDetailView.swift`: the Review button now shows only when `coffee.hasOpenReview &&
    reviewCache.hasReviewableTasks(for: coffee.id)`; added a second `.task` to prime the cache;
    the review sheet's `onFinished` now calls `reviewCache.refresh()` before re-loading detail, so
    finishing a review promptly re-hides the button if that was the coffee's last actionable item.
  - `RootTabView.swift`: `pendingReviewCount` (the Review tab's `.badge()`) now applies the same
    `hasReviewableTasks` gate, so the badge number matches what the tab's own feed-backed queue
    actually contains instead of counting every `needs_review` coffee.
  - `ReviewQueueView.swift` / `CoffeeReviewSheet.swift`: one-line `ReviewFeedCache.shared.adopt(feed)`
    added right after each existing `client.reviewFeed()` fetch — no other change needed, since
    accept/dismiss in both already route through `CoffeeStore.resolveReview(taskId:value:)`/
    `.dismissReview(taskId:)` (the durable `MutationOutbox` path, already wired by an earlier
    session — see the false-start note below for how that was confirmed rather than assumed).
  - **False start, caught before pushing**: first pass was written against `origin/main`'s copy of
    `CoffeeReviewSheet.swift`/`ReviewQueueView.swift`, which turned out to be stale — `main` hasn't
    had `ios-staging`'s last publish-merge, so its copies still fire-and-forget through a raw
    `APIClient` call instead of `store.resolveReview`/`.dismissReview`. Caught by diffing
    `origin/main` against `origin/ios-staging` for these exact files before committing; re-did the
    change against real `origin/ios-staging` content. Flagging because it's a live instance of the
    exact "which branch is actually current" trap `CLAUDE.md`'s gotchas section warns about — not
    a claim that `main`'s copy needs fixing (the Publish lane's normal merge replaces it).
  - Not locally compiled (no Xcode in this environment) — flag the compile lane to
    `Features/Review/ReviewFeedCache.swift` and the four call sites above specifically if the next
    compile check goes red. `@MainActor final class ... ObservableObject` with a `static let
    shared` singleton read via `@ObservedObject` is a pattern not used elsewhere in this codebase
    yet, so it's the most likely first thing to check.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-05 UTC] Session check — no ready `ios-ux` row (`#18`/`#27`/`#28` are
  the only ios-ux rows, all `done`). **Found and reconciled an off-lane
  commit pair**: `origin/main` carried two commits
  (`63ac9a5`/`9bb27d6`, "Review API: enrich feed..." / "iOS: wire Review tab
  to real backend...") from a different session that pushed straight to
  `main` instead of `ios-staging` — a violation of `CLAUDE.md` §5's dev/ship
  split (only the Publish lane may merge `ios-staging → main`; a push to
  `main` should never touch `ios/**` directly). Worse, it edited files across
  both iOS lanes in one commit: `API/APIClient.swift` + new
  `API/Wire/ReviewWire.swift` (shell-owned) alongside
  `Features/Review/{ReviewCardView,ReviewModels,ReviewQueueEngine,
  ReviewQueueView}.swift` + `Features/Coffees/CoffeeDetailView.swift`
  (ux-owned) — exactly the cross-boundary mixing the two-lane split exists to
  prevent, and it was never on `ios-staging` at all.
  - Not reverting it — the content itself is good and overdue: it closes the
    exact gap `#27`'s own `status/ios-ux.md` entry flagged ("no
    `CoffeeStore`/`APIClient` surface for `GET /api/review`") by adding
    `APIClient.reviewFeed()/.resolveReview()/.dismissReview()` and wiring
    `ReviewQueueEngine`'s `onAccept`/`onDismiss` hooks to them; it also
    replaced my `ReviewPhotoPlaceholder` with a real pinch-zoomable
    `AsyncImage` against the backend's new signed `thumbUrl`, and added the
    "Full text" disclosure on both the review card and `CoffeeDetailView`
    using the backend's newly-enriched raw title/caption/description. It also
    closes a follow-up ios-shell had flagged (`status/ios-shell.md`,
    2026-08-05): `ReviewFeedDTO` now decodes `items` via `FailableDecodable`,
    skipping one malformed row instead of failing the whole array.
  - `git checkout ios-staging && git merge origin/main` — clean on every
    `ios/**` file (auto-merged, including `CoffeeDetailView.swift`); the only
    conflict was an additive one in `status/backend.md` (two session-check
    entries at the same spot), resolved by keeping both.
  - Verified before pushing: every SF Symbol the new code references
    (`reviewOther`, `reviewZoom`, plus the ones already used) already exists
    in `DesignSystem/Symbols.swift` — no typo risk, no missing-symbol blank
    render. Read the new `APIClient`/`ReviewWire`/engine/view code in full;
    it's consistent with this lane's own conventions (fire-and-forget
    persistence, `AppConfig.shared`, no new dependencies). Swept
    `git branch -r --list 'origin/claude/*'` for stranded work in
    `Features/**`/`DesignSystem/**`/`Resources/**` — every non-zero candidate
    was either pre-lane-split scaffolding already known-superseded or exactly
    the two commits (`de55557`, `9bb27d6`) just merged from `main`; nothing
    else to adopt.
  - **Flagging, not fixing**: the new review persistence bypasses
    `MutationOutbox` entirely (fire-and-forget `Task { try? await
    client.resolveReview(...) }` in `ReviewQueueView.load()`) — offline or a
    failed call just leaves the row open server-side for a later `load()`,
    it doesn't retry or survive the pattern `MutationOutbox` gives favorites.
    `MutationOutbox`'s own doc comment already reserves a
    `.reviewResolution(taskId:value:)` case for this; not adding it myself
    since `Store/MutationOutbox.swift` is shell-owned and this is the same
    seam noted in `#27`'s original entry below, just not yet closed by this
    off-lane commit either.
  - No `BACKLOG.md` row change — `#27`/`#28` were already `done`; this is
    integration of already-landed content, not new scope.
  - Commit: `09acfb3` (merge), on `ios-staging`

- [2026-08-04 00:00 UTC] 27 Review queue — batch cards, photo auto-zoom, mapping rules — branch `ios-staging`
  - Unblocked by merging `origin/main` into `ios-staging`: each branch only knew half the picture (`ios-staging` had
    `#22` done but a stale `blocked` for backend's `#23`/`#24`/`#25`; `main` had `#23`/`#24` done but still showed
    `#22` as merely `ready`, since the shell lane never pushes to `main`). Reconciling the two is what surfaced `#27`
    as `ready` — recorded at the top of `status/BACKLOG.md`'s "Right now".
  - `Sources/Features/Review/{ReviewModels,ReviewSampleData,ReviewQueueEngine,ReviewCardView,ReviewBatchCardView,
    ReviewQueueView}.swift`, replacing `ReviewPlaceholderView.swift` (deleted) in `RootTabView`. New
    `DesignSystem/Symbols.swift` entries under "Review queue (#27)".
  - **Batch cards** (PLAN.md §6.5): tasks sharing `(field, rawValue)` across ≥8 collapse into one card ("N coffees
    say X → Y? [Accept all N] [Review individually]"); "Accept all" bulk-resolves and creates a mapping rule in one
    step, "Review individually" permanently un-collapses that group for the session via `expandedGroupKeys`.
  - **Queue order**: batch cards first (largest first), then remaining tasks grouped by coffee (`coffeeId ?? photoId`
    — a review item can predate coffee resolution, per the backend's own `LEFT JOIN coffees`) and ordered by fewest
    open fields first, then anything skipped-to-back at the very end. All computed fresh from `openTasks` on every
    read, same "plain computed property, not `@Published`" pattern as `CoffeeStore.filteredCoffees`.
  - **All five gestures** (PLAN.md §6.5's table): tap a chip or swipe right → accept, advance immediately; long-press
    a chip → accept **and** create a mapping rule applied to every *remaining* task with the same `(field, rawValue)`
    — not just the ones visibly batched, since a pair below the ≥8 threshold still benefits; swipe left → defer to
    the very back of the whole queue (`deferredIDs`, not just its own coffee group); swipe down → not-present,
    removed for the session; a 20-deep undo stack (`ReviewQueueEngine`'s private `undoStack`) with a 5 s auto-dismiss
    toast, plus a toolbar undo button so the 20-deep history stays reachable past the 5 s window.
  - **`ReviewField.aliasKind`** gates the long-press-creates-a-rule behaviour to the four fields the backend's
    `ALIAS_TABLES` actually persists (`originCountry`/`roasterCountry` → `country`, `roaster`, `farm`,
    `routes/review.js`) — long-pressing a profile/altitude/weight/price chip just accepts, matching what
    `POST /api/review/rules` can actually store.
  - **"Other…"** reveals a `TextField` only on demand, per PLAN.md §6.5's "the keyboard is the enemy of the budget."
  - **Flags from ISO codes** and **Every SF Symbol in `Symbols.swift`** conventions both followed; picked
    deliberately safe/common symbol names (`globe`, `storefront`, `leaf`, `link`, `square.and.pencil`,
    `arrow.up.left.and.arrow.down.right`) over exotic ones, given there's no local Xcode to catch a typo.
  - **One real gap, flagged rather than worked around: no real backend feed.** `CoffeeStore`/`APIClient`
    (shell-owned) expose no `GET /api/review`, `POST /api/review/:id`, `POST /api/review/bulk`, or
    `POST /api/review/rules` methods today — same gap class as #28's flagged `loadBrief()`. Built and ran the whole
    feature against `ReviewSampleData` (a local fixture built to exercise both queue-order rules: two batch groups of
    exactly the brief's own quoted examples, `Etiopia → Ethiopia` at 11 tasks and `DAK → DAK Coffee Roasters` at 9,
    plus per-coffee singles with 1/2/3 open fields to make "fewest-open-fields-first" visible) per the work loop's
    "build against `BundledSampleRepository`, zero backend dependency" instruction. Every engine action today only
    mutates local `@Published` state; nothing round-trips through `MutationOutbox` yet.
  - **What the shell lane would need to add, if picked up** (claimed here and in `status/ios-shell.md` per the seam
    rule in `status/README.md`): an `APIClient` method per backend route (`reviewItems(limit:offset:) async throws`,
    `resolveReview(id:value:) async throws`, `dismissReview(id:) async throws`, `createReviewRule(kind:canonicalId:
    alias:) async throws`) plus a `CoffeeStore`-level wrapper, mirroring `loadDetail`'s shape. `MutationOutbox`
    (`Store/MutationOutbox.swift`) already left room for this in its own doc comment ("leaves room for the review
    lane (#27) to add its own [`PendingMutation`] case without a new outbox") — a `.reviewResolution(taskId:value:)`
    case would let resolutions survive app restart/offline the same way favorites do. Not guessing the exact
    signatures further than that; flagging rather than reaching into shell-owned files.
  - **Also not done, deliberately out of scope**: no photo/OCR bounding-box auto-zoom, since no real photo URL or
    focus rect exists anywhere in the data yet (`Coffee.images.ocr` is nil for every sample row on purpose,
    `Models/Coffee.swift`'s own comment). Built `ReviewPhotoPlaceholder` as a fully pinch-zoomable, double-tap-to-reset
    component ready to swap an `AsyncImage`/`ImageStore` load into once that field exists, rather than faking image
    content into a public repo.
  - Not locally compiled (no Xcode in this environment) — flag the compile lane to `Features/Review/**` and the new
    `Symbols.swift` entries specifically if the next compile check goes red; the two most likely first things to
    check are the stacked `.onTapGesture`/`.onLongPressGesture` on `ReviewChip` and the `WrapLayout()` trailing-closure
    call syntax (matched exactly to the existing `CoffeeDetailView` usage).
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-02 00:00 UTC] No open `ios-ux` backlog row (`#27` still blocked on
  backend `#24`) — instead closed the UX-wiring gap the shell lane flagged in
  `status/ios-shell.md` after `#22` landed: `Thumbnail.swift` was still a plain
  `AsyncImage` instead of using the disk-cached, downsample-on-write
  `Store/ImageStore.swift` actor, the row heart had no tap target, and
  `CoffeeDetailView` never called `store.loadDetail(for:)` so real notes/images
  never populated past the compact snapshot. All three are presentation wiring
  inside owned paths — no new plumbing needed, both `CoffeeStore` methods
  already existed.
  - `Sources/DesignSystem/Thumbnail.swift` — replaced `AsyncImage` with a
    `.task(id: urlString)` that calls `ImageStore.shared.thumbnail(for:
    maxPixelSize:)` (sized by `size * @Environment(\.displayScale)`) and wraps
    the returned `CGImage` in `UIImage` for display; silently falls back to
    the existing placeholder on any failure. Used by both the 84pt row
    thumbnail and the 64pt detail-page inline thumbnail, so both got this for
    free.
  - `Sources/Features/Coffees/CoffeeRowView.swift` — added `@EnvironmentObject
    private var store: CoffeeStore` and wrapped the heart `Image` in a
    `Button { store.toggleFavorite(coffee) }` with `.buttonStyle(.plain)`.
    It's nested inside the row's `NavigationLink` label; SwiftUI hit-tests the
    inner `Button` first, so the tap doesn't fall through to row navigation
    (same pattern already used for the roaster/origin taps in
    `CoffeeDetailView`, not new territory).
  - `Sources/Features/Coffees/CoffeeDetailView.swift` — the view took `coffee:
    Coffee` as a plain stored property, so a `.task` alone wouldn't have shown
    the merge (the local copy never changes). Renamed the init parameter to
    `initialCoffee`, added a computed `private var coffee: Coffee {
    store.index.coffee(id: initialCoffee.id) ?? initialCoffee }`, and added
    `.task { await store.loadDetail(for: initialCoffee) }` on the root
    `ScrollView`. Every existing `coffee.*` reference in the file now reads
    through the computed property with zero other line changes, so once
    `loadDetail` merges the detail payload into `store.index`, the next body
    re-render (triggered by `index` being `@Published`) picks it up
    automatically.
  - **Flag for the shell lane, not acted on here:** `Store/ImageStore.swift`'s
    doc comment still says "Not yet wired into `DesignSystem/Thumbnail.swift`"
    — that's now stale, but the file is shell-owned so left it for you to
    update rather than editing out-of-lane.
  - No `BACKLOG.md` row for this (not new scope, just closing a flagged gap in
    already-owned files) — same precedent as the shell lane's `Profile`/
    `SortOption` `Hashable` fix on 2026-07-31.
  - Not locally compiled (no Xcode in this environment) — flag the compile
    lane to these three files specifically if the next compile check goes red.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-01 00:00 UTC] 28 Insights (statistical gates) + roaster/country entity pages — branch `ios-staging`
  - Picked up after checking `git branch -r --list 'origin/claude/*'` for stranded prior work on #28 — none found, so
    built fresh. #22 (ios-shell, remote repo/sync) had just landed on `ios-staging`, unblocking this row.
  - `Sources/Features/Insights/{InsightsStats,InsightsAggregation,InsightsFindings,InsightsCharts,InsightsView,
    DataQualityCard}.swift` + `Sources/Features/Insights/EntityPages/{RoasterPageView,CountryPageView}.swift`,
    replacing `InsightsPlaceholderView.swift` (deleted) in `RootTabView`.
  - **Gates exactly per PLAN.md §6.4** (`InsightsStats.swift`): categorical needs n ≥ 5 both sides and |Δmean| ≥ 0.08;
    ordinal (altitude/price/price-per-100g/purchase-year vs rating) uses Spearman ρ on fractional tie-aware ranks,
    gated n ≥ 20 and |ρ| ≥ 0.15. Every sentence states its n; ρ itself is shown (an effect size, not a p-value — the
    brief explicitly forbids p-values, not ρ). Capped at 12 sentences, ordered by effect size.
  - **The two additions the brief doesn't ask for, both built:** a Data quality card (per-field missing/total counts,
    pinned at the top, omitted entirely at 100% complete) and a within-year z-score toggle
    (`InsightsStats.withinYearZScores`) that swaps every categorical/ordinal comparison's rating input for a
    within-purchase-year z-score — a year with < 2 rated coffees or zero spread passes its points through unscored
    rather than dividing by zero. The year-vs-rating ordinal finding is suppressed in z-score mode since it would be
    tautologically ~0 by construction.
  - Charts: yearly stacked counts by origin country (top 6 + Other), by process (all 5 profiles + Unknown — no
    "Other" needed, fixed 6-value domain), by roaster (top 6 + Other), plus average rating by year with a dashed
    `RuleMark` at the all-time mean. All `BarMark`/`LineMark`/`PointMark`/`RuleMark` + `.chartForegroundStyleScale`
    (iOS 17-safe, no `BarPlot`/`LinePlot`/`Chart3D`). The process chart's color scale reuses `ProcessStyles`' exact
    hues via `overrideColors` so a color means the same profile it means in the listing tags, per PLAN.md §6.4's
    "colours are pinned... and matches the listing tags"; origin-country/roaster charts get a generic 6-color
    rotation with gray reserved for "Other".
  - **Entity pages resolve pushback #7 and #11.** `RoasterPageView`/`CountryPageView` (the latter parameterized by
    `CountryPageRole: .origin | .roaster` — a coffee's roaster-country and origin-country are different pages, not
    the same page reused) show a stats header (count, average rating) and a rating-ordered coffee list.
    `DesignSystem/MonogramAvatar.swift` adds the deterministic colored-initials avatar pushback #11 calls for — same
    name always hashes to the same color from a small fixed palette. **`Roaster` has no `blurb` field yet**
    (`Models/Vocab.swift`, shell-owned); the page simply omits that section rather than inventing the field or
    shipping an empty box. Flagging here rather than in `status/ios-shell.md` since it's not a claim, just a
    pointer — no action needed unless/until the data lane seeds one.
  - **Flipped both `FeatureFlags` to `true`** (`tapNavigatesToEntityPages`, `railMoreGoesToEntityPage`) now that the
    entity pages exist, and wired the actual navigation the flags gate: in `CoffeeDetailView`, the roaster-row flag
    now opens the roaster's country page, the roaster name opens the roaster page, and the origin pill opens the
    origin-country page (pushback #7's exact mapping) — each guarded by the flag with a static fallback, so flipping
    it back is still a one-line revert. `RailView`'s "More" now routes the roaster/origin rails to their entity page
    (`CoffeeRail.moreDestination`, a new field) instead of the bare `RailMoreView` list; the profile rail has no
    entity page and keeps the bare list unconditionally.
  - **Not done, flagged rather than guessed:** PLAN.md §6.4 says to "reuse the existing `/api/brief` + `briefs` table
    for a clearly separated 'This month' editorial section." `CoffeeStore`/`APIClient` (shell-owned) expose no
    brief-fetching method today, and this lane can't add one without touching `Store`/`API`. Rather than duplicate
    networking plumbing inside `Features` (which would fight the shell/UX seam this repo is built around), left it
    out of `InsightsView` with a doc-comment pointer here. **Shell lane:** if you'd like to add a
    `CoffeeStore.loadBrief()` (mirroring `loadDetail`'s shape — fetch, no local caching needed since it's a
    once-a-day read), claim it in both lane files and I'll wire the section in.
  - Built against `SampleCoffeeRepository`'s fixture (~22 records) — small enough that most gated findings correctly
    produce nothing (n ≥ 20 for ordinal is above the whole sample size), which is the gate working as intended, not
    a bug; verified by reading through the logic rather than running it (no local Xcode).
  - Commit: (see `git log` on `ios-staging`)

- [2026-07-30 00:00 UTC] 18 Design system + listing + filter sheet + sort + detail (sample data) — branch `ios-staging`
  - `Sources/DesignSystem/{Symbols,FeatureFlags,Flag,ProcessTag,WrapLayout,FilterPill,FactRow,Thumbnail}.swift` — every SF Symbol
    name centralized; process tags as light/dark hex pairs via `UIColor(dynamicProvider:)`; ISO-alpha2 → flag emoji per
    PLAN.md §6.6 (validated on the *input's* scalar count, not the result's); a ~50-line `WrapLayout: Layout` for
    variable-width filter pills.
  - `Sources/Features/Coffees/**` — `CoffeesListView` (`List` + `.listStyle(.plain)`, `.searchable`, top filter cards,
    sort menu, sticky sections per PLAN.md §6.1's per-sort header rule), `FilterSheetView` + `FacetFullListView`
    (`.presentationDetents([.large])`, top-8-then-"Show all", zero-count facets disabled at 30% opacity per §6.2),
    `CoffeeDetailView` + `RailView` (real `ToolbarItem` back/share so edge-swipe survives, rating-ordered rails omitted
    below 2 items, per §6.3), `SettingsSheet` (behind the toolbar gear), `CoffeeDisplay.swift` (view-layer presentation
    helpers over `Coffee`/`SortOption`/`FacetKey` — kept out of `Models`/`Query` since those are shell-owned).
  - `Sources/Features/{Insights,Review}/*PlaceholderView.swift` — tab reservations only; the real screens are #28/#27,
    both still blocked on #22/#24. `Review` carries its `.badge(pendingCount)` from `Coffee.hasOpenReview` already.
  - `Sources/Features/Root/RootTabView.swift` — the three-tab root (Coffees / Insights / Review), owns the single
    `CoffeeStore` instance and injects it via `.environmentObject`.
  - **Cross-boundary touches, both worth flagging:**
    1. **`Sources/ContentView.swift`** (root-level, not under either lane's glob in `status/README.md`) — swapped its
       placeholder body for `RootTabView()`. One line; the file's own doc comment invited exactly this ("grow into the
       real MyCoffee UI once the product brief lands"). `MyCoffeeApp.swift`/`ConnectView.swift` untouched.
    2. **`Models/Profile.swift` and `Query/SortOption.swift` (shell-owned) don't compile as committed.** Both are used
       in `Set<_>`/dictionary contexts (`CoffeeFilter.profiles: Set<Profile>`, `FacetKey.profile(Profile)`, a `Picker`
       binding to `SortOption`) that require `Hashable`, but neither type declares it — and Swift only synthesizes
       `Equatable`/`Hashable` from a type's *original* declaration file, so this isn't latent, it's a real build
       blocker nobody hit yet because the compile lane is still gated on #10. Rather than edit those files directly,
       manual `Hashable` conformance is added via extension in `Features/Coffees/CoffeeDisplay.swift` (`extension
       Profile: Hashable` / `extension SortOption: Hashable`, hand-written `==`/`hash(into:)`, not compiler-synthesized).
       **Shell lane:** if you'd rather declare `Hashable` directly on the originals, delete the two extensions here in
       the same commit — leaving both would be a duplicate-conformance error.
  - Everything builds against `SampleCoffeeRepository`'s ~22-record fixture; no backend/network dependency. Not
    locally compiled (no Xcode in this environment) — flag the compile lane to this file set specifically if the next
    compile check goes red, since the two `Hashable` extensions above are the most likely first thing to check.
  - Commit: (see `git log` on `ios-staging`)

## Abandoned

_none_
