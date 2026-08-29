# ios-ux — archived history

Moved out of `status/ios-ux.md` on 2026-08-28 (backlog #92) so a lane session
reads a small file. Nothing is edited or deleted here — sections are verbatim
and in their original order. Live claims stay in `status/ios-ux.md`; the
authoritative record of what is done is `status/BACKLOG.md`.

## Done

- [2026-08-29 UTC] Compile check confirmed green for the #93/#94/#99 push (`e48a7f2`) — run #81
  (`33244352775`), conclusion `success`.
- [2026-08-29 UTC] #93 Redesign v2 §A — screen chrome (`CoffeesListView.swift`) — branch `ios-staging`
  - A1: header lifted out of the `List` into a fixed `VStack { headerSection; searchField; List }`; native nav bar
    hidden (`.toolbar(.hidden, for: .navigationBar)`), both `.toolbarBackground` calls and `.toolbarColorScheme`
    removed. The blue band draws via `.background(Theme.Colors.accent.ignoresSafeArea(edges: .top))` on the
    non-ignoring `headerSection`, so content lands below the status bar while the colour extends under it — one
    band, not two. Padding tightened (top 8→4, bottom 20→10, title 36→30pt) to work toward the ≤108pt budget; not
    verified on-device (no local Xcode/simulator this session) — flagging for whoever runs the next compile/TestFlight
    build to eyeball against the `2a` reference.
  - A2: `.searchable` removed; new `searchField` row (plain `TextField` + `Symbols.search` magnifier in
    `neutral700`, inside `Capsule().fill(neutral100)`, `minHeight 44`, 22pt side margins) sits between the header and
    the `List`, on `Theme.Colors.surface`.
  - A4: `monthHeader` gets `.background(Theme.Colors.surface)` + `.listRowInsets(EdgeInsets())`.
    **DEVIATION** from the brief's literal `Color.white`: using the adaptive `surface` token instead, since pairing
    a literal with adaptive ink is the exact dark-mode bug `#100` fixed — `surface` is the same white in light mode.
  - A5: `headerIcon` ring (`Circle().strokeBorder`) removed. Sort + Settings folded into one `Menu` (reuses the
    existing `Symbols.settings` glyph, no new icon) with a `Picker("Sort")` and a `Button` for Settings inside;
    Filter stays a separate button since it has its own active/inactive icon state.
  - A6: `.listRowInsets(EdgeInsets())` added to the coffee-row `ForEach` (was already on `monthHeader` via A4).
    `CoffeeRowView`'s own padding (`.leading 22 / .trailing 16`) already matches the brief's target margin, so it
    was left untouched — not one of the files this row lists.
  - Added `Symbols.search = "magnifyingglass"` (`DesignSystem/Symbols.swift`) — the one new symbol name a plain
    search field needs; `Symbols.sort` is now unused (kept, harmless) since sort moved into the overflow menu using
    the existing settings glyph.
- [2026-08-29 UTC] #94 Redesign v2 §A3 — `+` moves into the bottom bar (`RootTabView.swift`) — branch `ios-staging`
  - System tab bar hidden (`.toolbar(.hidden, for: .tabBar)`), replaced with a real `.safeAreaInset(edge: .bottom)`
    three-slot bar (Coffees · (+) · Insights) built from two new `tabButton`s plus the existing `addCoffeeButton`
    (unchanged 56pt `#0078ff` circle/white 24pt plus/`md` shadow). Because it's a safe-area inset rather than an
    overlay, `CoffeesListView`'s `List` and `CoffeeDetailView`'s pushed content both inset above it — nothing
    overlaps, and it doesn't show on the detail page since that page lives inside the Coffees tab's own
    `NavigationStack`, not as a sibling of the `TabView`.
  - Simplified `TabView` to the plain `.tag()` form and dropped the iOS-18-only `Tab(value:)` builder — its whole
    reason to exist (docking `.searchable` near the bottom bar, `#58`) is moot now that `#93` replaced
    `CoffeesListView`'s `.searchable` with a plain in-page search field.
- [2026-08-29 UTC] #99 Bring the pie charts back to Insights, blue palette (`InsightsCharts.swift`,
  `InsightsView.swift`) — branch `ios-staging`
  - Adopted stranded prior work from `origin/claude/hopeful-johnson-motfkj` (commit `19f64f6`) rather than
    re-deriving Radu's decisions: the backlog row already carried "replace, use blue palette" plus the three
    ramp constraints and the dark-mode caveat before this session started.
  - Restored `PieSlice`/`CategoryPieChart` (donut + wrapped legend, `★4.3`-style per-slice average, tap-to-filter
    via `onSelect`) into `InsightsCharts.swift`, replacing `#89`'s `BreakdownCard` outright (decision 1: replace,
    not a third pill) — `BreakdownCard` deleted, nothing else referenced it.
  - New `ChartPalette.blueRamp`: 6 adaptive steps, **not** a reuse of `Theme.Colors.accent100...accent800` — those
    dark-mode values are tuned for on-`surface` *text* contrast and would land several ramp steps at a luminance
    close to `surface`'s near-black (`#141212`), washing slices into the background together (the exact risk #99
    flagged). Wrote 6 dedicated light/dark hex pairs instead, via `Theme.adaptive(light:dark:)` (un-`fileprivate`'d
    for this cross-file use) — light runs deep→pale, dark runs bright→medium, so "index 0" is always the strongest
    step against *that* theme's surface. Not verified on a physical dark-mode screenshot this session; flagging for
    on-device review per the row's own note.
  - `ChartPalette.blueRampColors(for:)` assigns steps by rank (slices arrive pre-sorted by count descending, so
    index *is* rank), cycling past 6 — the top-8+Other cap needs up to 8 colours from a 6-step ramp, so the two
    smallest kept slices can repeat a step; acceptable since the legend's label+count+rating is what carries
    identity now, never colour alone (constraint 3). "Other" is always neutral grey, never a ramp step.
  - `InsightsView.chartsSection` keeps `#89`'s dimension chip switcher and time-window control unchanged, just
    swapped what they feed: `pieSlices(for:facets:)` (top-8-by-count + Other, restored from the pre-#89 code) into
    `CategoryPieChart` instead of raw facet entries into `BreakdownCard`. Chart title is now `dimension.title`
    (e.g. "Origin country") rather than the old fixed "What you rate highest" — that copy was tied to
    `BreakdownCard`'s rating-ranked semantics, and slices here rank by value, not rating.
- [2026-08-27 UTC] #89 InsightsView + InsightsCharts redesign — see BACKLOG.md's own write-up for full detail

## Session notes

- [2026-08-27 UTC] `status/BACKLOG.md` on `main`'s copy (this session's starting
  branch) was stale relative to `origin/ios-staging`'s — #83–#88 were already
  `done` on `ios-staging`, same visibility gap the 2026-08-24+ sessions in
  this file already documented (main's dev/ship split means backend/data
  session checks never see ios-staging-only rows). Checked out `ios-staging`,
  merged `origin/main` in (one conflict in `status/BACKLOG.md`, same
  `main`-is-stale shape as the merge conflicts documented above — resolved by
  keeping `ios-staging`'s side, since it carries the actual completion
  write-ups `main`'s copy never received). While resolving, noticed `#82`
  (flavour-notes section) was still marked `ready` even though `#88`'s own
  write-up explicitly folds it in and closes it out — verified directly
  against `Features/Coffees/CoffeeDetailView.swift` (the FLAVOUR PROFILE chip
  section is live) before flipping it to `done`. Picked `#89` (the last open
  `ios-ux`/`ready` row: `#82` just corrected to `done`, `#85`–`#88` already
  `done`) — `InsightsView`/`InsightsCharts`/`BriefCard`/`DataQualityCard`
  redesign per `design/coffees_redesign/README.md` §Screen 3. `CategoryPieChart`
  (the old donut-per-dimension chart) is gone, replaced by a single
  `BreakdownCard` fed by a dimension chip switcher, ranked by average rating.
  Added one new `Theme.Colors.hairline` token (`#EAE7E7`) for the breakdown
  card's row dividers — the one genuinely new color this spec section
  introduces. Full detail + the two deliberate deviations from the literal
  mock (chip copy reuses `FilterDimension.title` instead of a second naming
  scheme; year chips get a small local `chip()` builder rather than a global
  `FilterPill` restyle, since that component is still used unrestyled by
  `FilterSheetView`/`FacetFullListView`, outside this row's scope) are in
  `status/BACKLOG.md`'s own `#89` row. Not locally compiled (no Xcode in this
  sandbox) — every removed symbol (`CategoryPieChart`, `PieSlice`,
  `pieDimensions`, `slices(for:facets:)`) was grep-verified to have no other
  call sites before deleting. `DesignSystem/Theme.swift`,
  `Features/Insights/{InsightsView,BriefCard,InsightsCharts,DataQualityCard}.swift`.

- [2026-08-26 UTC, same session as #87] **#88 DONE** — `CoffeeDetailView` 2a
  redesign, folds in #82 — branch `ios-staging`.
  - Picked up right after #87 (batching per the lane's normal guidance);
    #83/#84/#81 were all already `done` so #88 read `ready` with no further
    merge needed.
  - **Toolbar**: kept the established "no custom back button" precedent
    (this file's own pre-existing comment: a leading overlay back button
    previously produced a duplicate arrow and broke edge-swipe) instead of
    reproducing the handoff's leading back-circle pixel-for-pixel. Restyled
    the trailing Share/Edit to explicit 44×44 white-92%-opacity circles and
    added a new favourite circle (accent fill, white heart) — favourite
    wasn't on the toolbar before this row.
  - **Review pill**: needed a real per-coffee field count the app didn't
    expose yet — `ReviewFeedCache` (`Features/Review/**`, ios-ux-owned, so
    in-scope) only tracked a `Set<String>` of reviewable coffee ids. Added
    `reviewableFieldCounts: [String: Int]` alongside it (one feed item is
    one (coffeeId, field) pair, so counting items per coffee from the same
    already-fetched feed was free) and `reviewableFieldCount(for:)`. The
    pill now reads "2 fields to review" instead of a bare "Review" label.
  - **Roaster row**: reread the handoff text carefully here — "your best
    roaster" is the single #1 roaster (`topRoasterIDs().first`), a stricter
    bar than `#85`'s row-level "member of the top set" check, which #85's
    own doc comment already flagged as the detail page's distinction to
    make. The name itself is unconditionally blue now (handoff literally
    lists it as one of blue's fixed uses, same as the rating), unlike the
    row's conditional treatment.
  - **Pill row**: process moved out of its own tinted `ProcessTag` section
    and into the plain neutral pill row per Definition of done ("no tinted
    capsule for process"); omitted entirely (not "Unknown") when the coffee
    has no profile, matching `#85`'s precedent for the listing row. Origin
    pills only turn blue for an actual top-origin country — the handoff's
    prose lists origin as unconditionally blue-tinted, but that reads as
    inconsistent with its own Definition of done ("blue only for top
    roaster/origin") and with `#85`'s shipped row behaviour, so this session
    followed the stricter, already-established rule rather than the
    ambiguous prose.
  - **Price block + fact rows**: new stat-pair block replaces the old price
    fact-rows entirely; `DesignSystem/FactRow.swift` lost its icon/card
    styling (renamed `FactRowsCard`→`FactRowsList` since it isn't a card
    background anymore) and gained a "Farm" row via the already-existing
    `coffee.originFarm(vocabulary:)` accessor — the handoff asks for this
    row but nothing before this session actually surfaced it as a fact row.
  - **Flavour profile**: `Coffee.flavorNotes` (#81) is a comma-separated
    string, not an array — split/trim/filter into chips client-side, `nil`
    entirely omits the section (handles both "field absent" and the
    backend's empty-string "scanned, none stated" sentinel the same way).
  - **Rails**: `RailView.swift` restyled to the handoff's 13pt/11pt header
    and 92pt cards; dropped the star-glyph rating (plain blue/grey number,
    matching `#85`'s row-level removal of star glyphs).
  - Not locally compiled (no Xcode in this sandbox) — the riskiest pieces
    are `UnevenRoundedRectangle` (iOS 16+, fine for this iOS 17 target, but
    unused elsewhere in the codebase so worth a first look on a red compile)
    and the toolbar's three-circle layout at real device widths.
  - `Features/Coffees/{CoffeeDetailView,RailView}.swift`,
    `Features/Review/ReviewFeedCache.swift`, `DesignSystem/{FactRow,Theme}.swift`
    (added `Theme.minHitTarget`, missing from `#83`'s original token set).
    No other row's `needs` names `88` — nothing else unblocks.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-26 UTC] **#87 DONE** — `RootTabView` redesign (3 tabs → 2 tabs +
  centre add button + review nudge) — branch `ios-staging`.
  - Re-verified before picking up: this session started on the harness's
    generic per-repo branch (`claude/hopeful-johnson-yc6ywg`, which mirrors
    `main`), where `BACKLOG.md` still showed #83–#86 as `ready`/`blocked`.
    Checking `origin/ios-staging` directly (per `CLAUDE.md` §12's "a fired
    session commits to its own branch" gotcha and `status/README.md`'s
    "integrate before you start" rule) found #83–#86 already `done` there
    with real, distinct commits (`431ae54`, `32f8458`, `51e3abe`) and a
    `BACKLOG.md` already corrected to match — `main`'s copy was just stale.
    Discarded a duplicate `Theme.swift` this session had drafted before
    checking, and continued from `ios-staging`'s actual head instead of
    redoing #83.
  - **Tab bar**: `RootTabView.swift` drops the `Review` tab from both the
    iOS 18+ value-based `Tab` builder and the iOS 17 `.tabItem` fallback —
    down to Coffees/Insights only, `.tint(Theme.Colors.accent)` on the
    `TabView` for the active-tab colour. Did **not** touch `RootTab` (shell-
    owned, `Store/CoffeeStore.swift`) — its `.review` case is simply
    unreferenced now rather than deleted, since removing it would be a
    shared-surface change and nothing left in this lane's files needs it.
  - **Centre "+"**: restyled the existing #77 floating button with `Theme`
    tokens (56pt `Theme.Colors.accent` circle, white 24pt plus,
    `Theme.Shadow.md` via `themeShadow(_:)`) and moved its overlay alignment
    from `.bottomTrailing` to `.bottom`. **Did not build it as a real third
    `Tab`** — the handoff's "Coffees · + · Insights" wants a middle slot
    that opens a sheet rather than navigating, which needs a `Tab` whose
    selection is intercepted and reverted (a "fake tab" pattern), and that
    revert is visibly flickery with no simulator here to check. With only
    two real tabs the native bar already splits into two even halves, so a
    button centred at the bottom edge lands exactly on the seam between
    them — visually the same three-slot result, without the flicker risk.
    Flagging this trade-off in case a session with a simulator wants to
    swap in the "real third tab" version later.
  - **Review nudge**: no new work — #86 already built
    `CoffeesListView.reviewNudge`, gated on `store.reviewQueueCount > 0`,
    opening `ReviewQueueView` as a sheet. This row's badge-removal is now
    complete on both ends (no more `Review` tab badge, nudge is the only
    surface).
  - Typography fidelity note: the handoff asks for 9pt/0.1em-tracked tab
    labels — SwiftUI's native tab bar doesn't expose label typography short
    of replacing the whole bar with a custom view, which felt like too much
    risk for this row's actual ask (remove Review, add the centre button).
    Left tab labels as system default text at native size, matching the
    README's own "prefer system behaviours...over exact pixel matches"
    concession.
  - Not locally compiled (no Xcode in this sandbox) — the riskiest piece is
    the `.tint(Theme.Colors.accent)` interaction with #58's iOS-26
    `.searchable` bottom-docking (unrelated modifier, but same view); flag
    `RootTabView.swift` first on a red compile or a `.searchable` placement
    regression.
  - `Features/Root/RootTabView.swift`. No other row's `needs` names `87` —
    nothing else unblocks.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-26 UTC, same session as #85] **#86 DONE** — `CoffeesListView`
  redesign — branch `ios-staging`.
  - Picked up right after #85 in the same session (batching per the lane's
    normal 2–4-item guidance); #83/#84 both already `done` so #86 read
    `ready` with no further merge needed.
  - **Header**: rather than hiding the native nav bar outright (risking an
    interaction with #58's iOS-26 `.searchable` bottom-docking, which is
    keyed off `RootTabView`'s `Tab(value:)` builder, not this view's own
    bar), kept the bar but reduced it to an inline, colour-matched strip
    (`.toolbarBackground(Theme.Colors.accent, ...)`,
    `.toolbarColorScheme(.dark, ...)`, empty `navigationTitle`) and moved the
    actual "Coffees" title/overline/buttons into a custom `headerSection`
    List row with its own `Theme.Colors.accent` background — visually one
    continuous blue field even though it's two stacked pieces. Bag/roaster
    counts for the overline are computed client-side
    (`store.index.coffees.count` / `Set(...compactMap(\.roasterId)).count`)
    rather than needing a new `CoffeeIndex` helper.
  - **Review nudge**: new, gated on `store.reviewQueueCount > 0`, opens
    `ReviewQueueView` as a `.sheet` — the Review tab itself stays put until
    #87 actually removes it, so both routes coexist for now, which is fine
    (additive, not a conflict).
  - **Filter chips**: `TopFilterCardsRow.swift` deleted; a new inline chip
    view in `CoffeesListView.swift` styles pills per the handoff and
    implements the **new** tap-the-active-chip-to-clear behavior (the old
    view always set `store.filter = card.filter` regardless, never cleared
    on a repeat tap of the same card — confirmed by reading the deleted
    file before removing it, not just assuming). **Deliberately did not
    touch `Query/TopFilterCard.swift`** even though the backlog row's own
    file list named it — that file is `Query/**`, ios-shell-owned per
    `CLAUDE.md` §4, and its existing `title`/`count`/`filter` shape already
    covers everything the restyled chip needs, so there was nothing to
    change there anyway.
  - **Filter-state line + month headers**: straightforward per spec — the
    line uses `store.filteredCoffees.count`/`store.index.coffees.count` and
    a `CLEAR` button resetting `store.filter = CoffeeFilter()`; month
    headers move from a plain `Section(String)` to a `Section(content:
    header:)` with a styled `Text` (uppercase, 10pt, tracked, `neutral700`,
    no background) so the existing sticky-header behavior (a `List`/
    `.listStyle(.plain)` property, not tied to header type) is unaffected.
  - **Flagging, not guessing silently**: two pieces have no way to visually
    confirm without a simulator — (1) whether the nav-bar-tint + custom-row
    header combination actually reads as one continuous blue field or shows
    a visible seam/double-header, and (2) whether the now-empty
    `navigationTitle("")` changes the back-button label when pushing into
    `CoffeeDetailView` (cosmetic only — a bare chevron instead of "Coffees"
    — not a functional break). Next compile/device check should look at
    `CoffeesListView.swift` first for either.
  - Not locally compiled (no Xcode in this sandbox).
  - `ios/MyCoffee/Sources/Features/Coffees/CoffeesListView.swift`; deleted
    `ios/MyCoffee/Sources/Features/Coffees/TopFilterCardsRow.swift`.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-26 UTC] **#85 DONE** — `CoffeeRowView` 2a redesign — branch `ios-staging`.
  - **Before claiming**: this session started on `claude/hopeful-johnson-ohtwjx`
    with an in-progress, not-yet-committed draft of `#83` (design tokens +
    accent) already written locally. Checking out `ios-staging` and merging
    `origin/main` in surfaced that `#83` **and** `#84` (ios-shell's derived
    values, `ValueRating`/`TopVocabAverage`/`valueBand`/`topRoasterIDs`/
    `topOriginCountryIDs` in `Store/CoffeeIndex.swift`) had already landed on
    `origin/ios-staging` (`431ae54`, `32f8458`) from an earlier firing the
    same day — confirmed by diffing the stashed draft against the landed
    `Theme.swift` (byte-for-byte equivalent token table and `AccentColor`
    sRGB values) before discarding it, per the "integrate before you start"
    rule. Resolved a real merge conflict in `status/BACKLOG.md` (rows
    `#80`–`#82`: `ios-staging`'s copy had the fuller, more-recent write-ups —
    `#80`'s backfill marked COMPLETE, `#81` DONE not `ready` — kept those over
    `origin/main`'s stale versions, same "keep the newer/fuller side"
    precedent prior sessions have used). With `#83`/`#84` both `done`, `#85`
    through `#89` all read `ready` — picked `#85` (lowest number, and the
    suggested-implementation-order's "biggest visible win, self-contained").
  - **The redesign**: rewrote `CoffeeRowView.swift` against `Theme.*` and
    `design/coffees_redesign/README.md` §Row — 88×88 `Thumbnail` (no
    grayscale; the README's own Assets note says that's a mock convention,
    not a requirement) with the favourite as a bottom-trailing-pinned 44×44
    hit area around a 28pt circle (blue+white heart when favourite, white+
    outline heart otherwise); middle column drops the roaster-country flag
    (2a moves it off the row per the README) and renders roaster name
    uppercase/10pt, blue only when the roaster is in
    `store.index.topRoasterIDs()`; title 17/800; origin line keeps the flag,
    appends `· <avg>` and turns `accent700` only when one of the coffee's
    origin countries is in `store.index.topOriginCountryIDs()` (picking the
    highest-average match for a blend); process renders as plain 11pt grey
    text, no capsule — `ProcessTag`/`DecafBadge` are gone from this view
    entirely (not called out as "keep" anywhere in the row spec, and the
    capsule is explicitly in the "removed" list). Right column: rating 26/800
    (blue at ≥4.5, no star glyph), price, a compact `€X.XX/100g` line, then a
    5-pip value meter + verdict text from `store.index.valueBand(for:)`
    (`GREAT VALUE`/`FAIR VALUE`/`PRICEY`, blue only for `.great`). The old
    full-width grey date-strip footer is deleted outright — the README is
    explicit that the purchase date now lives in the month header only, which
    `CoffeesListView` already renders — so the row no longer needs a `sort`
    parameter at all; removed it from the initializer and updated all four
    call sites (`CoffeesListView`, `RailView.RailMoreView`,
    `CountryPageView`, `RoasterPageView`). Kept `PlainDateFormatting` in this
    file (still used by `CoffeeDetailView.swift`) even though this view no
    longer calls it itself.
  - **Interpretation call, flagged rather than guessed silently**: the README
    says a roaster/origin "qualifies when it is in the user's highest-average
    set with at least ~5 rated bags" — read as **membership** in
    `topRoasterIDs()`/`topOriginCountryIDs()`'s returned array (which is
    already filtered to `count >= minCount` and sorted by average), not
    literally just the single best entry (`#88`'s "your best roaster, 4.6
    avg" on the detail page is the `.first`-of-that-array case, a distinct,
    narrower use of the same derived value). If Radu's read differs once he
    sees it on device, the fix is a one-line `.first`-vs-`.contains` swap in
    `isTopRoaster`/`topOriginAverage`.
  - Not locally compiled (no Xcode in this sandbox) — flag
    `CoffeeRowView.swift` first on a red compile check; the one API used here
    with no existing in-app precedent is `Text.tracking(_:)` for the
    letter-spacing values (`0.6`/`-0.34`/`0.8`pt, converted from the
    handoff's em-relative-to-font-size values) — real API since iOS 16, well
    under the iOS 17 deployment target, so a failure here is far more likely
    a typo than the API not existing.
  - `ios/MyCoffee/Sources/Features/{Coffees/{CoffeeRowView,CoffeesListView,
    RailView},Insights/EntityPages/{CountryPageView,RoasterPageView}}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-25 UTC] **#83 DONE** — Coffees/Coffee-page/Insights redesign (2a),
  design-tokens foundation. Added `ios/MyCoffee/Sources/DesignSystem/Theme.swift`:
  `Theme.Colors` (the full handoff hex table — accent/accent600/accent100/
  accent200/accent700/accent800/neutral100/neutral300/neutral700/neutral900/
  text/surface), `Theme.Radius` (photo 10, pill 999, card 20), `Theme.Shadow`
  (`sm`/`md`, both `neutral900`-tinted per the handoff's `rgba(45,43,43,…)`
  spec, plus a `themeShadow(_:)` view modifier), `Theme.Weight` (regular/
  semibold/heavy — CSS 400/600/800 mapped onto SwiftUI's matching `Font.Weight`
  raw values). Flipped `Resources/Assets.xcassets/AccentColor.colorset` from
  brown `#a5824c` to `#0078ff` (srgb 0.000/0.471/1.000 — `0x78/255 = 0.4706`
  rounds to `0.471`). Deliberately touched nothing else — this row is pure
  foundation for #84–#89, and every downstream row references `Theme.*` rather
  than re-deriving hex values, so there's no shared-file race between them.
  Not locally compiled (no Xcode in this sandbox); the hex→sRGB arithmetic was
  hand-checked instead. Flipped #83 `ready`→`done` in `status/BACKLOG.md`, and
  #86/#87 `blocked`→`ready` (both only needed #83; #85/#88/#89 stay `blocked`
  on #84/#81, which are ios-shell's rows, still `ready` not `done`). Merged
  `origin/main` into `ios-staging` first (clean, one BACKLOG.md line + the
  #81 flavour-notes migration/backend work, no conflicts). Pushing to
  `ios-staging` only, per the lane rule.

- [2026-08-25 UTC] No-op session. `status/BACKLOG.md`: swept the entire table —
  every row is `done`, `human` (#65), or `dropped` (#30). `#75`/`#76`/`#77` (Add
  Coffee wizard, backend/ios-shell/ios-ux) are all `done` and confirmed live in
  the merged tree, not just row text: `ios/MyCoffee/Sources/Features/AddCoffee/
  AddCoffeeWizardView.swift` exists, and `git log` shows `1c2b8a7`/`7c79946`/
  `74cc73f` already on `ios-staging`. No `ios-ux` row (or any row) is
  `ready`/`blocked`/`claimed`. Swept `git branch -r --list 'origin/claude/*'` —
  only this session's own branch (`hopeful-johnson-y1c1vl`) exists, nothing
  stranded to adopt. Merged `origin/main` into `ios-staging` (clean, one file —
  `status/backend.md` gained a new session-note entry, no code, no conflicts).
  Stopping cleanly per the lane's documented no-op behaviour; no feature code
  changed.

- [2026-08-24 UTC] Integrated stranded `#76` + built `#77` (Add Coffee wizard
  UI) — branch `ios-staging`.
  - **Before claiming**: merged `origin/main` into `ios-staging` (clean — #75,
    backend's Add Coffee wizard half, had just landed). Rescanned
    `status/BACKLOG.md`: `#77` (this lane) was `blocked` on `#76`
    (ios-shell), which was itself `ready`, not `done` — so nothing qualified
    yet under the normal pick-a-`ready`-row rule. Per the "integrate before
    you start" protocol, swept `git branch -r --list 'origin/claude/*'`
    (133 branches — the usual large stranded-branch backlog every session in
    this file has documented) and, instead of another size-based spot-check,
    grepped all of them for the wizard's own symbols
    (`extractDraft|createCoffee|AddCoffeeWizard|ExtractedDraft|uploadPhotos`)
    across `ios/MyCoffee/Sources`. One real hit:
    `claude/wizardly-thompson-e42ekb`, touching exactly the ios-shell-owned
    paths (`API/`, `Models/`, `Store/`, `Utilities/`) `#76` needed. Its own
    two commits ("iOS shell: Add Coffee wizard — repository surface (#76)",
    "iOS shell: correct #76 status — code complete, not yet integrated")
    plus `status/ios-shell.md`'s `## Claimed` entry (read from that branch)
    confirmed it: the ios-shell session that built it could only push to its
    own fired-session branch, so it explicitly asked "whoever integrates it"
    to merge it into `ios-staging` and flip `#76`→`done`/`#77`→`ready` in the
    same push. The branch was based on current `ios-staging` (merge-base =
    its own tip), a pure 333-insertion/0-deletion addition — merged with no
    conflicts.
  - Flipped `#76`→`done` (recording the integration + landing merge commit)
    and `#77`→`done` in `status/BACKLOG.md` in the same session that built
    `#77` against the now-integrated surface — did **not** touch
    `status/ios-shell.md` (never edit another lane's file), even though its
    own note asked the integrator to move its claim to `## Done` there; that
    edit is left for the ios-shell lane itself.
  - **`#77` (Add Coffee wizard UI)**: new `Features/AddCoffee/
    AddCoffeeWizardView.swift` — see the full write-up in `status/
    BACKLOG.md`'s `#77` row rather than duplicating it here. Short version:
    3-step sheet (photos → paste text → confirm), a new `DraftFieldRow`
    reusing `ReviewField`'s label/symbol table and the review queue's
    chip-then-edit visual language (not the literal private `ReviewChip`
    type — `DraftField` has no task id or accept/dismiss actions to hang it
    off), one "Save coffee" button calling `#76`'s
    `CoffeeStore.createWizardCoffee`. Entry point is a floating "+" overlaid
    on `RootTabView`, not a fourth tab — keeps the "three tabs" decision
    intact. Two new `Symbols` entries (`wizardAdd`, `wizardPhotos`).
  - Not locally compiled (no Xcode here). Two real unknowns flagged for the
    compile lane: whether `PhotosPicker`/`PhotosPickerItem.loadTransferable`
    (iOS16+ API, first use in this codebase) compiles clean against this
    project's actual SDK/target, and whether `PhotosUI` needs an explicit
    framework entry in `project.yml` (shell-owned, not touched here — most
    Swift-overlay system frameworks auto-link on `import`, but this project's
    XcodeGen config wasn't inspected to confirm).
  - `ios/MyCoffee/Sources/{Features/AddCoffee/AddCoffeeWizardView,
    Features/Root/RootTabView,DesignSystem/Symbols}.swift`
  - Commit: `74cc73f`/`7c79946` (`#76`, replayed in directly by the final
    `git pull --rebase` rather than staying a separate merge commit) +
    `1c2b8a7` (`#77`, this session's own commit) on `ios-staging`

- [2026-08-24 UTC] No-op session. Merged `origin/main` (`50b7d46`) into
  `ios-staging` cleanly — brings in `#75` (backend, Add Coffee wizard backend
  half), which is now `done`. That unblocked `#76` (ios-shell) to `ready`, but
  `#76` itself hasn't landed yet, so this lane's `#77` (Add Coffee wizard UI,
  needs `76, 27`) stays `blocked`. No other row in the table is
  `ios-ux`/`ready`. No `Features/`/`DesignSystem/`/`Resources/` files touched.

- [2026-08-23 UTC, later session] No-op session. `status/BACKLOG.md` on
  `ios-staging` (merged `origin/main` clean, only `status/publish.md`
  changed): unchanged — `#75` (backend, Add Coffee wizard backend half) is
  still the only `ready` row anywhere in the table. `#76` (ios-shell) stays
  `blocked` on `#75`; `#77` (this lane) stays `blocked` on `#76` (`#27` is
  already `done`). No other row is `ios-ux`/`ready`. No files touched.

- [2026-08-23 UTC] No-op session. `status/BACKLOG.md` on `ios-staging`
  (`9e1fc14`, fast-forwarded cleanly, no merge needed): unchanged again — `#75`
  (backend, Add Coffee wizard backend half) is still the only `ready` row
  anywhere in the table. `#76` (ios-shell) stays `blocked` on `#75`; `#77`
  (this lane, the Add Coffee wizard UI) stays `blocked` on `#76` (`#27` is
  already `done`). Nothing else in the table is `ios-ux`/`ready`. No files
  touched.

- [2026-08-22 UTC, later session] No-op session. `status/BACKLOG.md` on
  `ios-staging` (`6aac5f0`, which this session already had checked out — no
  fast-forward needed): unchanged since the prior two checks — `#75` (backend,
  Add Coffee wizard backend half) is still the only `ready` row anywhere in the
  table. `#76` (ios-shell) stays `blocked` on `#75`; `#77` (this lane, the
  wizard UI) stays `blocked` on `#76` and `#27` (done). No `ios-ux` row
  qualifies. `origin/main` is still at `469cfbe` (a backend "no ready row"
  session check) — confirmed directly by reading `origin/main:status/BACKLOG.md`
  (858 lines, tops out at row `#74`): `#75`–`#77` don't exist there at all,
  because `ios-shell` filed them on `ios-staging` (`650cadf`) rather than on
  `main`, and backend — which reads/pushes only `main` — has no way to see a
  `ready` row that only exists on the other branch until the Publish lane
  merges `ios-staging` into `main`. This is the same dev/ship-split visibility
  gap `status/ios-shell.md`'s 2026-08-21 entry already diagnosed in detail; not
  a new finding, and not something this lane (also confined to `ios-staging`)
  can fix by pushing anywhere.
  Re-swept `git fetch origin --prune` (130 `origin/claude/*` branches, matching
  the last sweep's count) and spot-checked the five highest-ranked-by-commit-
  count candidates this session hadn't individually verified yet
  (`confident-cerf-{4xuqov,55g4kl,fod7ez,fti5j5}`, `hopeful-johnson-3hio6h`) via
  `git diff --stat ios-staging..origin/<branch> -- Sources/{Features,
  DesignSystem} Resources` — all five are net-negative (e.g. "249 insertions,
  801 deletions"), stale pre-current forks, same shape every prior sweep has
  found. Also checked `git log --all --grep` for any stray branch actually
  implementing `#75`/`#76`/`#77`'s wire surface (`coffees/extract`, etc.) —
  none exists; the only two "Add Coffee wizard" commits anywhere
  (`f8e227b`/`49d03b6`, both already reconciled into `#75`–`#77` by `650cadf`)
  touch only `PLAN.md`, no code. Nothing stranded to adopt. Stopping cleanly
  per the lane's documented no-op behaviour; no feature code changed. (No
  merge needed this session — already at `ios-staging`'s current tip with
  `origin/main` an ancestor.)

- [2026-08-22 UTC] No-op session. `status/BACKLOG.md` on `ios-staging`: the only
  `ready` row anywhere in the table is `#75` (backend, Add Coffee wizard —
  backend half). `#76` (ios-shell, same feature) is `blocked` on `#75`; `#77`
  (this lane, the wizard UI) is `blocked` on both `#76` and `#27`. No `ios-ux`
  row qualifies (status `ready`, lane `ios-ux`, all `needs` `done`).
  Swept `git branch -r --list 'origin/claude/*'` (130 branches) via
  `git rev-list --count ios-staging..origin/<branch> -- ios/MyCoffee/Sources/Features
  ios/MyCoffee/Sources/DesignSystem ios/MyCoffee/Resources` — every branch came
  back `0`, nothing stranded to adopt. Merged `origin/main` into `ios-staging`
  (one conflict, in `status/backend.md` — two backend session-note blocks
  appended at the same spot on divergent history, same recurring pattern prior
  sessions have documented; resolved as a union, kept both, no code involved).
  Stopping cleanly per the lane's documented no-op behaviour; no feature code
  changed.

- [2026-08-21 UTC] No-op session. `status/BACKLOG.md` on `ios-staging`: the
  only `ready` row anywhere in the table is `#75` (backend — Add Coffee wizard
  backend half). This lane's own next item, `#77` (wizard UI), is `blocked` on
  `#76` (ios-shell), which is itself `blocked` on `#75` — no `ios-ux` row
  qualifies (`ready`, lane match, all `needs` `done`). Swept
  `git branch -r --list 'origin/claude/*'` — only this session's own branch
  exists and touches nothing under `Sources/Features`, `Sources/DesignSystem`,
  or `Resources`, so nothing stranded to adopt. Merged `origin/main` into
  `ios-staging` (one conflict, in `status/backend.md` — two backend
  session-check entries appended at the same spot on divergent history, same
  recurring pattern; resolved as a union, kept both). `BACKLOG.md` itself
  merged clean — `main`'s copy predates `#75`–`#77` (filed on `ios-staging`
  only, per the dev/ship split, so `main`'s own backend session-check that
  same day correctly saw no ready row there). Stopping cleanly per the lane's
  documented no-op behaviour; no feature code changed.

- [2026-08-21 UTC] No-op session. `status/BACKLOG.md`: confirmed independently
  (scanned the whole table, not just `ios-ux` rows) that every row is `done`
  except `#30` (`dropped`) and `#65` (`human`, data-lane) — no
  `ready`/`blocked`/`claimed` row exists anywhere, same conclusion the
  2026-08-20 session below already reached. `#57`/`#73`/`#74` (persisted photo
  rotation, the deadlock that ran 2026-08-15→2026-08-20) are all still `done`.
  Merged `origin/main` into `ios-staging` (clean — only `status/backend.md`
  session-note additions, no code). Swept `git branch -r --list
  'origin/claude/*'` — only this session's own branch exists, touching nothing
  under `Sources/Features`, `Sources/DesignSystem`, or `Resources`. Stopping
  cleanly per the lane's documented no-op behaviour; no feature code changed.

- [2026-08-20 UTC, later session] No-op session. `status/BACKLOG.md` (checked
  post-merge, not the stale pre-merge copy): every numbered row is `done`,
  `human`, or `dropped` — no `ios-ux` row is `ready`/`claimed`/`blocked`.
  `#57` (persisted photo rotation, the row that was deadlocked 2026-08-15 →
  2026-08-20) is now fully landed: `#73` (backend column + endpoint) and `#74`
  (ios-shell model/API/store) both `done`, and `#57`'s own ios-ux half (rotate
  button in the `#55` `ZoomableImageView` + `.rotationEffect` at
  `CoffeeDetailView`/`Thumbnail.swift`) shipped in the same session
  (`59c24c4` + a thumb follow-up) — confirmed live in the merged tree, not
  just the row text: `DesignSystem/Thumbnail.swift` has the new
  `rotationQuarterTurns` param, `CoffeeDetailView.swift` wires
  `ZoomableImageView`'s `onRotate` to `CoffeeStore.setRotation`. The table's
  own "Right now" narrative was one step behind this (still describing the
  `#73`/`#74` filing as the open item) — the row statuses are authoritative
  and all three are `done`.
  Merged `origin/main` into `ios-staging` (clean, no conflicts — brought in
  `#73`/`#74`'s backend+shell code plus a `PLAN.md` update). Swept
  `git branch -r --list 'origin/claude/*'` (117 branches) for stranded work
  touching `Sources/Features`/`Sources/DesignSystem`/`Resources`: most hit
  non-zero commit counts, but every sampled branch (the ones with the largest
  counts — `hopeful-johnson-bdpy3r`, `confident-cerf-{9y3vqr,j8in2k,t1flso,
  4xuqov,55g4kl,fod7ez,fti5j5}`, `modest-newton-oml7h8`) diffs as strongly
  net-negative against current `ios-staging` (e.g. "249 insertions(+), 801
  deletions(-)") — same "stale pre-current fork" shape every prior sweep in
  this file has documented, just at a much higher branch count now. Nothing
  stranded to adopt. Stopping cleanly per the lane's documented no-op
  behaviour; no feature code changed.

- [2026-08-20 UTC] No-op session. `origin/ios-staging` already had `origin/main`
  merged in (backend's own 2026-08-20 session check + the ios-shell lane's
  2026-08-20 merge, both no-ops) — `git merge-base --is-ancestor origin/main
  origin/ios-staging` confirms it, nothing to merge. Re-scanned
  `status/BACKLOG.md`: `#57` (persisted photo rotation) remains the only
  `ready` `ios-ux` row anywhere in the table (`needs: 59`, done), but it's
  still the same unbuildable seam every session since 2026-08-16 has
  independently confirmed — a fresh repo-wide `grep -rn
  "rotation_quarter_turns|rotationQuarterTurns"` outside `status/*.md` still
  returns zero hits: neither backend's column/write-endpoint/snapshot field
  nor ios-shell's model/API surface exists yet, so this lane's half (rotate
  button in `CoffeeDetailView` + the #55 viewer) has no concrete field to
  write through. Swept `git branch -r --list 'origin/claude/*'` — only this
  session's own branch exists (the large stranded-branch backlog prior
  sessions flagged, 87→114, is gone from this listing now), touching nothing
  under `Sources/{Features,DesignSystem}` or `Resources`. Nothing to adopt.
  Stopping cleanly per the lane's documented no-op behaviour; no feature code
  changed.

- [2026-08-19 UTC] No-op session. `status/BACKLOG.md`: `#57` (persisted photo
  rotation) remains the only `ready` `ios-ux` row (`needs: 59`, and `#59` is
  `done`), but its own row still names a seam this lane can't build alone —
  backend owns the `rotation_quarter_turns` column + write endpoint +
  snapshot field, ios-shell owns the model field + API + apply-on-display.
  Repo-wide grep for `rotation_quarter_turns`/`rotationQuarterTurns` outside
  `status/*.md` prose: still zero hits — neither piece exists yet, same
  conclusion every prior session since 2026-08-16 reached. Merged
  `origin/main` into `ios-staging` (clean, no conflicts). Swept
  `git branch -r --list 'origin/claude/*'` (114 branches) for stranded work
  touching `Sources/{Features,DesignSystem}/**` or `Resources/**`: an initial
  `git rev-list --count` pass flagged ~90 branches with non-zero diffs (a
  much larger set than prior sweeps), but a targeted `git grep` for the
  rotation seam symbols across every branch found matches only inside
  `status/*.md` narrative text (a red herring from `ref:path`-prefixed output
  not matching a naive `^status/` filter) — zero real code hits. Spot-checked
  two of the largest-diff branches (`hopeful-johnson-bdpy3r`,
  `confident-cerf-9y3vqr`) directly: both net-negative against current
  `ios-staging` (120/155 insertions vs. 198/445 deletions), the same
  stale-pre-fork shape every previous sweep in this file has already
  documented. Nothing to adopt. Stopping cleanly per the lane's documented
  no-op behaviour; no feature code changed.

- [2026-08-19 UTC] No-op session. `origin/ios-staging` was already up to date with `origin/main`
  (`git pull origin ios-staging` reported "Already up to date") — nothing to merge. Re-scanned
  `status/BACKLOG.md`: `#57` (persisted photo rotation) remains the only `ready` `ios-ux` row
  anywhere in the table, `needs: 59` (done). Independently re-verified it's still unbuildable —
  `grep -rn "rotation_quarter_turns\|rotationQuarterTurns" .` (excluding `status/`) across the whole
  repo returns zero hits in `backend/**`, `ios/**` Swift, or SQL migrations, confirming neither the
  backend column/write-endpoint/snapshot field nor the ios-shell model/API surface this row's
  ios-ux half needs to write through exist yet. Same conclusion every session back to 2026-08-17
  has independently reached.
  Swept `git branch -r --list 'origin/claude/*'` — **114 branches**, up sharply from the last
  documented count (87, per this file's 2026-08-13 entry). Spot-checked the largest by diff size
  touching `Sources/Features`/`Sources/DesignSystem`/`Resources`
  (`confident-cerf-{9y3vqr,j8in2k,t1flso}`, `hopeful-johnson-bdpy3r`): all are net-negative diffs
  against current `ios-staging` (e.g. "221 insertions, 660 deletions"), the same stale-pre-fork
  shape every prior sweep in this file has documented — nothing to adopt. Also grepped every one of
  the 114 branches' diffs for `rotation_quarter_turns`/`rotationQuarterTurns` specifically (in case a
  stranded branch had built exactly the seam `#57` is waiting on) — zero hits anywhere. **Flagging,
  not fixing**: 114 stranded `claude/*` branches is a lot of dead weight for future sweeps to wade
  through; this is the kind of thing `CLAUDE.md` §12's "if lanes keep producing orphan branches, add
  a small integration routine" note anticipated, but pruning/merging them isn't this lane's call to
  make unilaterally. Stopping cleanly per the lane's documented no-op behaviour; no feature code
  changed.

- [2026-08-18 UTC, later session] Integrated a stray `main`-direct #66 fix; still no buildable `ios-ux` row.
  - `git fetch origin main ios-staging` showed `origin/main` had moved two commits ahead of what
    `ios-staging` had merged: `3234d68` ("iOS #66: save each review action live") and a backend
    `parseAltitude` fix. `3234d68` touches **both** `Features/Review/**` (this lane) and `Store/**`
    (shell) — a real code change landed straight to `main` instead of `ios-staging`, the exact
    "commits bypass the dev branch" footgun `CLAUDE.md` §12 documents, just in the reverse direction
    from its own worked examples. It also **corrects this lane's own 2026-08-16 "VERIFIED ALREADY
    CORRECT" call on #66** — that trace found the outbox enqueue was synchronous (true) but missed
    that the outbox only reliably *flushes* to the server on a later full sync, so a partial review
    session's accepts could sit un-sent, exactly matching Radu's "a 150-item queue can't be cleared
    in one sitting" report. `git merge origin/main` into `ios-staging` was clean (no conflicts —
    `ios-staging` had never touched these files since the earlier no-op verification made no code
    change). Read the full diff before accepting it: `resolveReview`/`dismissReview` now send
    directly and `throw`; `ReviewQueueEngine.onAccept`/`.onDismiss` became `async -> Bool` hooks
    awaited via a new `confirmSave(_:at:_:)` that re-inserts a task on a failed save instead of
    dropping it — mirrors the already-landed `#41`/`#42` edit-field confirm pattern, coherent with
    this codebase's conventions. Corrected `status/BACKLOG.md` #66's own text to record the real fix
    over the superseded verification note.
  - Re-checked `#57` (the only `ready` row): still unbuildable — repo-wide grep for
    `rotation_quarter_turns`/`rotationQuarterTurns` still empty outside status-file prose, no
    backend column/endpoint or shell model field exists yet. Swept `git branch -r --list
    'origin/claude/*'` — nothing new touching `Sources/Features`/`Sources/DesignSystem`/`Resources`
    beyond what prior sweeps already dismissed. Stopping cleanly — no `ios-ux`-owned feature work to
    do this cycle, but the integration itself was real, not a pure no-op.
  - Not locally compiled (no Xcode here) — the merged-in diff is a stray session's own work, already
    described as landed; flag `ReviewQueueEngine.swift`'s new `confirmSave`/`restore` pair first if a
    compile check goes red here.
  - `ios/MyCoffee/Sources/Features/Review/{CoffeeReviewSheet,ReviewQueueEngine,ReviewQueueView}.swift`
    (+ shell's `Store/**` half, same commit)
  - Commit: merge on `ios-staging` (see `git log`)

- [2026-08-18 UTC] Session check — no ready `ios-ux` row. Merged `origin/main`
  into `ios-staging` (clean, only `status/backend.md` gained a new entry —
  no conflicts with `Features/`/`DesignSystem/`/`Resources/`). Re-scanned
  `status/BACKLOG.md`: `#57` (persisted photo rotation) is the only `ready`
  row anywhere in the table, tagged `ios-ux`, `needs: 59` (done). But it's a
  seam row — the backend column/write-endpoint and the shell model/API
  surface it depends on don't exist yet (confirmed via a repo-wide grep for
  `rotation_quarter_turns`/`rotationQuarterTurns`: zero hits outside
  status-file prose). `status/ios-shell.md`'s own 2026-08-18 entry reached
  the identical conclusion the same day. Nothing in `#57`'s ios-ux half
  (rotate button in `CoffeeDetailView` + the #55 viewer) can be built without
  a concrete field to write through, so building ahead of the backend/shell
  halves would mean guessing the wire shape. Swept
  `git branch -r --list 'origin/claude/*'` — only this session's own branch
  exists, nothing stranded to adopt. Stopping cleanly per the lane's
  documented no-op behaviour; no feature code changed.

- [2026-08-17 UTC] 71 (ios-ux half) Filter-sheet time window + carry window/years on chart-tap deep-link — branch `ios-staging`
  - `git branch -r --list 'origin/claude/*'` showed only this session's own branch, nothing stranded
    touching `Sources/Features`/`Sources/DesignSystem`/`Resources` to adopt. Fetched and rebuilt
    `ios-staging` from `origin/ios-staging` (which already carried ios-shell's same-day #71(a) seam —
    `Query/{CoffeeFilter,RelativeWindow}.swift`, `Store/CoffeeIndex.swift` — confirmed live by
    grepping for `relativeWindow` in `CoffeeIndex.swift` before writing anything). #57 (the other
    `ready` row) checked and confirmed still unbuildable — no backend column/endpoint or shell model
    field for photo rotation exists yet (repo-wide grep for `rotation_quarter_turns` empty), same
    conclusion `status/ios-shell.md`'s same-day entry independently reached. Picked #71 instead of
    stopping.
  - **(a) Filter sheet**: `Features/Coffees/FilterSheetView.swift` gets a new "Time window" `Section`
    (added after the `ForEach(FilterDimension.allCases)` loop, so it sits right after the Year
    section) holding a new private `RelativeWindowRow` — a plain segmented `Picker` (All/12m/18m)
    bound directly to `draft.relativeWindow`, using the same `Optional<T>`-tag pattern
    `CoffeeEditSheet.swift`'s Process picker already established (`Text("All").tag(RelativeWindow?
    .none)`, `Text("12m").tag(Optional(RelativeWindow.last12m))`). Deliberately kept off the
    `FilterDimension`/`DimensionPills` per-value-count loop — same reasoning ios-shell's own #71(a)
    write-up gives: it's a single active toggle, not a multi-select facet with a "count if cleared"
    question to answer. Labels are the short "12m"/"18m" already used by `InsightsView.windowControls`
    rather than `RelativeWindow.label`'s longer "Last 12 months" (that string exists for
    accessibility/other call sites, not this segmented control).
  - **(b) Chart-tap carries the window**: `Features/Insights/InsightsView.swift`'s
    `selectInCoffees(dimension:key:)` now also sets `filter.relativeWindow` from a new
    `currentRelativeWindow` computed property (`.last12m`/`.last18m` map straight across, `.all`/
    `.years` → `nil`) and, when the Charts tab's own `window == .years`, copies `selectedYears` into
    `filter.years` too — the row's own "window/selectedYears" phrasing named both. Both existing call
    sites (`chartsSection`'s per-dimension legends, `#50`; `findingsSection`'s subject links, `#53`)
    get this for free since they both go through the one `selectInCoffees` function.
    `selectUnknownInCoffees` (`#54`, Data tab) is untouched — the Data tab has no window control to
    carry.
  - Not locally compiled (no Xcode here) — both changes are small, additive, and mirror an
    already-compiling pattern each (`Profile?` optional-Picker-tag; the existing
    `.last12m`/`.last18m` short-label convention), so a red compile check here is more likely a typo
    than a design gap.
  - `ios/MyCoffee/Sources/Features/{Coffees/FilterSheetView,Insights/InsightsView}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-17 UTC] 70 Altitude edit won't save a single value (only max) — branch `ios-staging`
  - **Before claiming**: merged `origin/main` into `ios-staging` (one real conflict in
    `status/BACKLOG.md` rows `#66`/`#67` — both sides had edited the same rows off a
    common parent: `ios-staging` had verified `#66` `done` and origin/main had the fuller
    `#67` `claimed` write-up; kept `ios-staging`'s `#66` and `main`'s `#67`, both are the
    newer/more-complete version of their respective row). Swept `git branch -r --list
    'origin/claude/*'` (105 branches) via `git rev-list --count ios-staging..<branch> --
    ios/MyCoffee/Sources/Features ios/MyCoffee/Sources/DesignSystem
    ios/MyCoffee/Resources` — dozens of non-zero hits, spot-checked the most-recently-dated
    ones plus every `hopeful-johnson-*` (this lane's own naming family): all but one are
    non-ios-ux branches (0 hits after checkout) or pre-#18/#27/#28 stale forks (net
    deletions), same pattern every prior sweep in this file found. The one real candidate,
    `hopeful-johnson-bdpy3r` ("iOS UX #58: dock listing search near the tab bar", dated
    2026-08-15), is an earlier alternate attempt at `#58` — confirmed superseded, not
    stranded: `#58` is already `done` and live on `ios-staging` via a different, later
    commit (`4f10408`, the `#available(iOS 18.0,*)` + `Tab(value:)` approach documented in
    this file's 2026-08-16 entry). Not adopted.
  - Rescanned `BACKLOG.md` for the actual next `ios-ux` row: `#57` (`ready`, needs `59`
    which is `done`) is next by number, but its own text and `status/ios-shell.md`'s
    2026-08-17 session check both confirm the backend column/write-endpoint and the
    ios-shell model/API surface it needs don't exist yet — "nothing concrete to build
    against" per that lane's own words. Picked `#70` instead (lowest number that's
    actually buildable standalone in ios-ux-owned files), same judgment call the shell
    lane made skipping `#57` for the identical reason.
  - **Root cause, confirmed by reading the code directly**: `CoffeeEditSheet.swift`
    `buildEdits()`'s altitude block gated the entire edit on `if let minValue =
    Int(altitudeMin)` — leaving `min` blank and only filling `max` skipped the block
    entirely, so nothing saved, exactly the row's own repro.
  - **Fix**: `let lo = Int(altitudeMin) ?? Int(altitudeMax)`, `let hi = Int(altitudeMax) ??
    Int(altitudeMin)`, then `minValue = min(lo, hi)` / `maxValue = max(lo, hi)` — fires
    when either field parses (both blank → both `nil` → skipped, as before), and as a
    bonus sanity-orders the pair if the user enters them swapped (min > max), which the
    row's own text asked for as a secondary fix. A single value in either field now sends
    a point altitude (`"2000 m"`), which `backend/src/lib/normalize.js`'s `parseAltitude`
    already accepts.
  - Not locally compiled (no Xcode here) — a narrow, mechanical change to one `if let`
    condition inside an already-existing, already-used function; low compile risk.
  - `ios/MyCoffee/Sources/Features/Coffees/CoffeeEditSheet.swift`
  - Commit: (see `git log` on `ios-staging`)
  - **Flagging, not building past ownership**: `#71` (chart time-window on the listing
    filter) is the next `ios-ux` row by number, but part (a) is a seam change to
    `Query/{CoffeeFilter,CoffeeIndex,FilterDimension}.swift` — shell-owned, not this
    lane's to edit — before there's a `relativeWindow`/equivalent field for a filter-sheet
    UI or a tap-carry-window fix to build against. Same judgment as `#57`: don't guess at
    the wire shape, wait for the shell half to land. Nothing written to
    `status/ios-shell.md` (never edit another lane's file) — the row's own text in
    `BACKLOG.md` already documents the seam for whichever lane picks it up next.

- [2026-08-16 UTC, later session] 68 "Unknown" bucket not selectable outside Process — branch `ios-staging`
  - **Before claiming**: swept `git branch -r --list 'origin/claude/*'` — only this session's own branch
    exists, 0 commits ahead of `ios-staging` in any owned path, nothing stranded to adopt. Merged
    `origin/main` into `ios-staging` first (clean fast-forward, no conflicts — picked up backend's #56/#60
    write-ups and publish's routine-ship note, no code touching owned paths).
  - **Found the backlog's own copy of this file badly stale before touching any code**: `status/BACKLOG.md`
    on `ios-staging` still listed `#50`/`#53`/`#54`/`#55`/`#58` as `ready`, but the code (and this lane's own
    prior session write-ups just above/below) already fully implements every one of them —
    `Features/Insights/{InsightsView,InsightsCharts,InsightsFindings,DataQualityCard}.swift` all have the
    `onSelect`/`selectInCoffees`/`FindingSubject`/`dimension`-gated-`Button` wiring `#50`/`#53`/`#54`
    describe; `DesignSystem/ZoomableImageView.swift` exists and is wired into both
    `Features/Review/ReviewCardView.swift` and `Features/Coffees/CoffeeDetailView.swift` per `#55`;
    `Features/Root/RootTabView.swift` already branches `#available(iOS 18.0, *)` into the value-based
    `Tab(...)` builder per `#58`. `status/ios-shell.md`'s own latest entry independently confirms the same
    ("#50/#52/#53/#54/#55 are all `done` on `origin/ios-staging`"). Also re-verified `#66` (Review per-item
    save) directly against `ReviewQueueEngine.accept`/`.markNotPresent` (call `onAccept`/`onDismiss`
    synchronously, same call as the local queue mutation, no batching), `CoffeeStore.resolveReview`/
    `.dismissReview` (fire immediately, not deferred to a "done" step), and `MutationOutbox.enqueueReviewResolve`/
    `.enqueueReviewDismiss` (call `persist()` synchronously right after enqueueing) — the exact
    force-quit-after-2-of-N scenario the row asks to verify is already durable. Corrected all six rows to
    `done` in `status/BACKLOG.md` (same "correcting a task means correcting this file" rule
    `status/README.md` names) rather than re-implementing already-shipped work. `#57` stays `ready` but
    unpicked — confirmed via `status/ios-shell.md`/`status/backend.md` that no backend column/endpoint or
    shell model/API exists yet for the rotation seam, so there's nothing concrete for this lane's half
    (rotate button + wiring) to call yet; building it blind would be guessing at a wire shape, the exact
    thing this lane's own precedent (`#27`/`#28`'s flagged gaps) avoids.
  - **The actual `#68` fix**: `Features/Coffees/FacetFullListView.swift`'s `isTappable()` special-cased
    `dimension == .profile` as the only dimension allowed to select its Unknown bucket — a stray leftover
    gate, since `FilterSheetView.swift`'s inline pill grid (`DimensionPills`) already had the correct
    5-dimension allowlist (`unknownSelectable: [.roaster, .roasterCountry, .originCountry, .farm, .profile]`)
    the row's own diagnosis names. Promoted that allowlist out of `DimensionPills` (where it was
    `private`) to a file-scope `unknownSelectableDimensions` constant next to the already-shared
    `isFacetSelected`/`toggleFacet` helpers, and pointed both `DimensionPills.isTappable` and
    `FacetFullListView.isTappable` at the single shared constant — closes the row's own "check the inline
    filter-sheet path uses the same gate" ask by construction (one definition, not two copies that can
    drift again) rather than just copy-pasting the same five-dimension list a second time.
  - Not locally compiled (no Xcode here) — a small, mechanical change against an existing pattern
    (`unknownSelectableDimensions` is used exactly the way the old `private static` set was), so a red
    compile check here would most likely be a typo, not a design gap.
  - `ios/MyCoffee/Sources/Features/Coffees/{FacetFullListView,FilterSheetView}.swift`
  - No `BACKLOG.md` row lists `68` as a `needs` dependency, so nothing to unblock.
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-16 UTC] 58 Move the listing search box to the bottom (iOS 26 style) — branch `ios-staging`
  - **Before claiming**: swept `git branch -r --list 'origin/claude/*'` — nothing stranded touching
    `Sources/Features`/`Sources/DesignSystem`/`Resources`. Merged `origin/main` into `ios-staging`
    (two conflicts, both in `status/BACKLOG.md`/`status/backend.md` — pure additive session-note
    entries appended at the same spot on divergent history, same recurring pattern; resolved as a
    union, kept both). **Also found and fixed a real pre-existing bug while merging**: `BACKLOG.md`
    carried rows `#56`–`#60` duplicated verbatim (a merge artifact from an earlier reconciliation,
    not new content) — removed the duplicate copy so a future lowest-number scan doesn't get
    confused by phantom repeat rows. Re-scanned after dedup: the only `ios-ux` row genuinely `ready`
    this cycle was `#58` (`#57` lists `needs: 59`, and `#59` — data lane, EXIF-orientation fix — is
    itself still `ready`, not `done`, so `#57` isn't actually pickable despite its own `ready` status
    predating that check).
  - **Root cause**: `RootTabView.swift` built its `TabView` with the legacy `.tabItem`/`.tag()` pair.
    iOS 26's new bottom-tab-bar-integrated search treatment only applies to tabs declared with the
    value-based `Tab(_:systemImage:value:)` builder (iOS 18+) — the legacy `.tabItem` form keeps
    rendering the old top-nav-bar search field regardless of SDK/OS version.
  - **Fix, gated for the iOS 17.0 deployment target** (`CLAUDE.md` §9 — no post-17 API without
    `#available`): `RootTabView.swift`'s body now branches `if #available(iOS 18.0, *)` between the
    modern `Tab("Coffees", systemImage:value:) { CoffeesListView() }` / `Tab("Insights", …)` /
    `Tab("Review", …) { ReviewQueueView() }.badge(store.reviewQueueCount)` builders, and an `else`
    branch keeping the original `.tabItem`/`.tag()` structure byte-for-byte as the iOS 17 fallback.
    `CoffeesListView.swift`'s `.searchable(text: $store.filter.query, prompt:…)` call is untouched —
    same binding, same prompt — per the row's own "placement only" framing; only the tab declaration
    it's nested under changed, which is what iOS 26 keys off to relocate the field.
  - **Flagging, not guessing past it**: the exact trigger for iOS 26's bottom-search placement (does
    plain `Tab(value:)` + `.searchable` on its content suffice, or does it need an explicit `role:`
    or placement modifier too?) can't be visually confirmed without a simulator/device — no Xcode in
    this sandbox. Deliberately did **not** reach for `Tab(role: .search)` — that adds a distinct
    4th tab-bar affordance, which would break the "three tabs: Coffees/Insights/Review" decision
    already made (`CLAUDE.md`, `RootTabView`'s own doc comment). If the compile lane's build still
    renders search at the top on a real device, next thing to check is whether an explicit role/
    placement modifier is needed — a behavior gap, not a syntax one (the `Tab(...)` initializer
    itself is real, stable API since iOS 18, so a red compile check here is more likely a typo in
    my usage than the API not existing).
  - Not locally compiled (no Xcode here) — flag the compile lane to `RootTabView.swift` first if the
    next check goes red; the `#available(iOS 18.0, *)`/`Tab(...)` branch is the only unproven-by-
    precedent piece in this file, everything else (the `.tabItem` fallback, `CoffeesListView`'s
    unchanged `.searchable` call) mirrors what was already there.
  - `ios/MyCoffee/Sources/Features/{Root/RootTabView,Coffees/CoffeesListView}.swift`
  - Commit: (see `git log` on `ios-staging`)

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

