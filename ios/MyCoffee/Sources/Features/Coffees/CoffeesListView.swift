import SwiftUI

/// The Coffees tab (Redesign **v3 §1, §2, §4, §5, §7, §10**,
/// `design/coffees_redesign/UPDATE_BRIEF.md`). v3 reverses v2's
/// chrome-replacement: the custom blue header band and the hand-built search
/// pill are gone. This is a plain `NavigationStack` with a **native
/// large-title** bar, **native `.searchable`**, and the system tab bar
/// (`RootTabView`) — content blurs under both. Everything that used to be
/// chrome is now content:
/// - the `411 BAGS · 59 ROASTERS` stats line is the first scrolling list row,
/// - the filter chips are the next content row (frosted glass unselected,
///   solid blue selected),
/// - month headers are quiet grey text on the surface, ~20pt apart,
/// - two trailing toolbar items: a **Sort** menu and a visible **Settings**
///   gear (settings is never buried in the sort menu).
///
/// `List` + `.listStyle(.plain)` gives sticky headers and real cell reuse.
struct CoffeesListView: View {
    @EnvironmentObject private var store: CoffeeStore
    /// #151: the review nudge counts the *filtered* subset while a filter is
    /// active, which needs the per-coffee reviewable set, not just the total.
    @ObservedObject private var reviewCache = ReviewFeedCache.shared

    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var showReviewQueue = false

    var body: some View {
        // #179c: `filteredCoffees` re-runs `CoffeeIndex.coffees(matching:sortedBy:)`
        // over the whole library on every access; the body used to call it
        // three separate times (the empty check, the review count, the
        // section grouping) on every render. Bound once here and threaded
        // through instead.
        let coffees = store.filteredCoffees
        return NavigationStack {
            List {
                // #150 (Radu, 2026-09-07: "reduce white space — now coffees
                // start below mid screen"): the header used to stack a stats
                // line AND a filter-state line. They say the same kind of
                // thing, so while a filter is active the stats line becomes
                // the filter-state line instead of sitting above it — one row
                // back, and the count is where the eye already was.
                if store.filter.isEmpty {
                    statsLine
                } else {
                    filterStateLine(coffees: coffees)
                }

                let reviewCount = visibleReviewCount(in: coffees)
                if reviewCount > 0 {
                    reviewNudge(count: reviewCount)
                }

                let cards = store.topFilterCards
                if !cards.isEmpty {
                    filterChipsSection(cards)
                }

                ForEach(sections(for: coffees)) { section in
                    Section {
                        ForEach(section.coffees) { coffee in
                            coffeeRow(coffee)
                        }
                        .plainListRow()
                    } header: {
                        monthHeader(section.header)
                    }
                }

                if coffees.isEmpty {
                    ContentUnavailableView(
                        "No coffees match",
                        systemImage: Symbols.emptyCup,
                        description: Text("Try clearing some filters.")
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            // §5: the ~20pt separation between sections comes from the month
            // header's own top inset, not List's default inter-section gap
            // (which produced the screen-height hole in v2).
            .listSectionSpacing(0)
            // #100: 2a assumes a `surface` ground everywhere; without these the
            // system supplies black under adaptive ink in dark mode.
            .scrollContentBackground(.hidden)
            .navigationTitle("Coffees")
            .navigationBarTitleDisplayMode(.large)
            // §2: native search — system placement and appearance, no custom pill.
            .searchable(
                text: $store.filter.query,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search coffees, roasters, farms"
            )
            .toolbar {
                // Advanced facet filter (Radu, 2026-09-07: "I want the filter
                // sheet back in the toolbar") — leading, so it doesn't crowd the
                // Sort/Settings pair. Glyph reflects whether a filter is active.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        // #149a (Radu, 2026-09-07: "blue on white… to see
                        // activated"). The two states used to be
                        // `Color.accentColor` vs `Theme.Colors.accent` —
                        // visually the same blue, so nothing changed when a
                        // filter was on. Now: outline glyph when idle, a
                        // solid blue disc behind a white glyph when active.
                        AppIcon(name: Lucide.listFilter, size: 20)
                            .foregroundStyle(
                                store.filter.isEmpty ? Theme.Colors.accent : Theme.Colors.onAccent
                            )
                            .frame(width: 32, height: 32)
                            .background {
                                if !store.filter.isEmpty {
                                    Circle().fill(Theme.Colors.accent)
                                }
                            }
                    }
                    .accessibilityLabel(store.filter.isEmpty ? "Filter" : "Filter, active")
                }
                // §1/§11: Sort — Lucide sliders-horizontal, opens the sort menu.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $store.sort) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    } label: {
                        AppIcon(name: Lucide.slidersHorizontal, size: 22)
                    }
                    .accessibilityLabel("Sort")
                }
                // §1/§11: a visible Settings gear (Lucide) — never buried in the sort menu.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        AppIcon(name: Lucide.settings, size: 22)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable {
                await store.refresh()
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(store: store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $showReviewQueue) {
                ReviewQueueView()
            }
            .task {
                if store.index.coffees.isEmpty {
                    await store.load()
                }
            }
            .task {
                // #151 needs the per-coffee reviewable set to scope the nudge
                // to the filtered subset. Fails open: until this resolves,
                // `visibleReviewCount` is the library-wide count as before.
                await reviewCache.ensureLoaded()
            }
            // #191: clamps to a readable column on iPad landscape/wide
            // multitasking — a no-op on iPhone. Carries the surface
            // background the List used to paint itself (still scrolls edge
            // to edge, but the visible content stops stretching full-width).
            .readableWidth(background: Theme.Colors.surface)
        }
    }

    // MARK: - Rows

    /// The whole row is the tap target and there is **no disclosure chevron**
    /// (§6): a full-size, zero-opacity `NavigationLink` sits behind the row
    /// content, so the List draws no indicator while any tap still navigates.
    /// The favourite `Button` inside `CoffeeRowView` is hit-tested first, so it
    /// never falls through to navigation.
    private func coffeeRow(_ coffee: Coffee) -> some View {
        ZStack {
            NavigationLink {
                CoffeeDetailView(coffee: coffee)
            } label: {
                EmptyView()
            }
            .opacity(0)

            CoffeeRowView(coffee: coffee, vocabulary: store.index.vocabulary)
        }
    }

    // MARK: - Stats line (§1)

    private var headerStats: String {
        let bagCount = store.index.coffees.count
        let roasterCount = Set(store.index.coffees.compactMap(\.roasterId)).count
        return "\(bagCount) BAGS · \(roasterCount) ROASTERS"
    }

    /// #151 (Radu, 2026-09-07: "when filtered — update x need review"). The
    /// nudge used to print `store.reviewQueueCount`, which is library-wide and
    /// did not move when you filtered — so a filtered list of 12 could claim
    /// "41 bags need review" while showing none of them.
    ///
    /// Fails open exactly like `ReviewFeedCache` itself: with no resolved feed
    /// (sample builds, offline, first launch) this is the old library-wide
    /// count, never a spurious 0.
    private func visibleReviewCount(in coffees: [Coffee]) -> Int {
        guard !store.filter.isEmpty, let reviewable = reviewCache.reviewableCoffeeIds else {
            return store.reviewQueueCount
        }
        return coffees.reduce(into: 0) { total, coffee in
            if reviewable.contains(coffee.id) { total += 1 }
        }
    }

    private var statsLine: some View {
        Text(headerStats)
            .font(.system(size: 10, weight: Theme.Weight.semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            .padding(.vertical, 6)          // #150: was 10
            .plainListRow()
    }

    // MARK: - Review nudge

    private func reviewNudge(count: Int) -> some View {
        Button {
            showReviewQueue = true
        } label: {
            HStack(spacing: 6) {
                Text("\(count) bag\(count == 1 ? "" : "s") need review")
                    .font(.system(size: 12, weight: Theme.Weight.semibold))
                AppIcon(name: Lucide.chevronRight, size: 12)
            }
            .foregroundStyle(Theme.Colors.accent700)
            // #150: 44 -> 38. Still a comfortable tap target for a row that
            // spans the full width; 44 was buying vertical space for nothing.
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 22)
        }
        .buttonStyle(.plain)
        .plainListRow()
    }

    // MARK: - Filter chips (§4, §12)

    private func filterChipsSection(_ cards: [TopFilterCard]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cards) { card in
                    filterChip(card)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 2)          // #150: was 4
        }
        .plainListRow()
    }

    private func filterChip(_ card: TopFilterCard) -> some View {
        let isActive = store.filter == card.filter
        // §12: unselected chips are frosted glass; selected is solid blue —
        // the glass-vs-solid contrast is what shows selection.
        return TogglePill(
            title: card.title,
            count: card.count,
            isSelected: isActive,
            unselectedFill: .material,
            titleFont: .system(size: 12),
            minHeight: 40,          // #150: was 44
            verticalPadding: 6      // #150: was 7
        ) {
            store.filter = isActive ? CoffeeFilter() : card.filter
        }
    }

    // MARK: - Filter state line

    /// #149b: the count **and** what is actually being filtered on. The chips
    /// only cover the ≤7 top-filter shortcuts, so a filter assembled in the
    /// sheet showed no trace of itself here before `FilterSummary`.
    private func filterStateLine(coffees: [Coffee]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(coffees.count) of \(store.index.coffees.count) bags")
                    .font(.system(size: 11, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                if let summary = FilterSummary.text(
                    for: store.filter,
                    vocabulary: store.index.vocabulary
                ) {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.neutral700)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            Button("CLEAR") {
                store.filter = CoffeeFilter()
            }
            .font(.system(size: 11, weight: Theme.Weight.semibold))
            .foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .plainListRow()
    }

    // MARK: - Month headers (§5)

    private func monthHeader(_ title: String) -> some View {
        EyebrowLabel(text: title, tracking: 1.4)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            // §5: plain grey text on the surface — no black band, no rule. The
            // 20pt top inset is the only separation between sections.
            // DEVIATION from the brief's literal `Color.white`: `surface` is the
            // same white in light mode and avoids re-introducing #100's
            // literal-on-token dark-mode bug (a sticky white label over dark rows).
            // #150: 20/10 -> 14/6. §5's "~20pt separation" was measured
            // before the header stack grew; the list now starts high enough
            // that the month gap can be tighter without sections running together.
            .listRowInsets(EdgeInsets(top: 14, leading: 22, bottom: 6, trailing: 22))
            .background(Theme.Colors.surface)
    }

    // MARK: - Sectioning

    private struct CoffeeListSection: Identifiable {
        let header: String
        let coffees: [Coffee]
        var id: String { header }
    }

    /// Coffees arrive from `CoffeeIndex.coffees(matching:sortedBy:)` already
    /// ordered, and every sort's section key is monotonic along that order,
    /// so a single contiguous-run pass is enough.
    private func sections(for coffees: [Coffee]) -> [CoffeeListSection] {
        let index = store.index
        var result: [CoffeeListSection] = []
        var currentHeader: String?
        var currentCoffees: [Coffee] = []

        for coffee in coffees {
            // #113: goes through the index, not `SortOption` directly — the
            // `.value` sort's section header is the coffee's value band, which
            // only the index knows.
            let header = index.sectionLabel(for: coffee, sort: store.sort)
            if header != currentHeader {
                if let currentHeader {
                    result.append(CoffeeListSection(header: currentHeader, coffees: currentCoffees))
                }
                currentHeader = header
                currentCoffees = [coffee]
            } else {
                currentCoffees.append(coffee)
            }
        }
        if let currentHeader {
            result.append(CoffeeListSection(header: currentHeader, coffees: currentCoffees))
        }
        return result
    }
}
