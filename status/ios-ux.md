# Lane: iOS UX

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Session notes

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
