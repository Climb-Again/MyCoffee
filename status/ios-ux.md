# Lane: iOS UX

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Session notes

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
