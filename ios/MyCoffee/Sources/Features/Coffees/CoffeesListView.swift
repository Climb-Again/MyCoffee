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

    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var showReviewQueue = false

    var body: some View {
        NavigationStack {
            List {
                statsLine

                if store.reviewQueueCount > 0 {
                    reviewNudge
                }

                let cards = store.topFilterCards
                if !cards.isEmpty {
                    filterChipsSection(cards)
                }

                if !store.filter.isEmpty {
                    filterStateLine
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.coffees) { coffee in
                            coffeeRow(coffee)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } header: {
                        monthHeader(section.header)
                    }
                }

                if store.filteredCoffees.isEmpty {
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
            .background(Theme.Colors.surface)
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
                        // §11: Lucide list-filter (Radu supplied it 2026-09-07);
                        // tinted accent while a filter is active.
                        AppIcon(name: Lucide.listFilter, size: 22)
                            .foregroundStyle(store.filter.isEmpty ? Color.accentColor : Theme.Colors.accent)
                    }
                    .accessibilityLabel("Filter")
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

    private var statsLine: some View {
        Text(headerStats)
            .font(.system(size: 10, weight: Theme.Weight.semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            .padding(.vertical, 10)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: - Review nudge

    private var reviewNudge: some View {
        Button {
            showReviewQueue = true
        } label: {
            HStack(spacing: 6) {
                Text("\(store.reviewQueueCount) bag\(store.reviewQueueCount == 1 ? "" : "s") need review")
                    .font(.system(size: 12, weight: Theme.Weight.semibold))
                AppIcon(name: Lucide.chevronRight, size: 12)
            }
            .foregroundStyle(Theme.Colors.accent700)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 22)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func filterChip(_ card: TopFilterCard) -> some View {
        let isActive = store.filter == card.filter
        return Button {
            store.filter = isActive ? CoffeeFilter() : card.filter
        } label: {
            HStack(spacing: 7) {
                Text(card.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Theme.Colors.onAccent : Theme.Colors.neutral900)
                Text("\(card.count)")
                    .font(.system(size: 12, weight: Theme.Weight.semibold))
                    .foregroundStyle(isActive ? Theme.Colors.onAccent : Theme.Colors.neutral700)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            // §12: unselected chips are frosted glass; selected is solid blue —
            // the glass-vs-solid contrast is what shows selection.
            .background {
                if isActive {
                    Capsule().fill(Theme.Colors.accent)
                } else {
                    Capsule().fill(.thinMaterial)
                }
            }
            .overlay(
                Capsule().strokeBorder(isActive ? Theme.Colors.accent : Theme.Colors.neutral300, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter state line

    private var filterStateLine: some View {
        HStack {
            Text("\(store.filteredCoffees.count) of \(store.index.coffees.count) bags")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.neutral700)
            Spacer()
            Button("CLEAR") {
                store.filter = CoffeeFilter()
            }
            .font(.system(size: 11, weight: Theme.Weight.semibold))
            .foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Month headers (§5)

    private func monthHeader(_ title: String) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: Theme.Weight.semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.Colors.neutral700)
            .frame(maxWidth: .infinity, alignment: .leading)
            // §5: plain grey text on the surface — no black band, no rule. The
            // 20pt top inset is the only separation between sections.
            // DEVIATION from the brief's literal `Color.white`: `surface` is the
            // same white in light mode and avoids re-introducing #100's
            // literal-on-token dark-mode bug (a sticky white label over dark rows).
            .listRowInsets(EdgeInsets(top: 20, leading: 22, bottom: 10, trailing: 22))
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
    private var sections: [CoffeeListSection] {
        let coffees = store.filteredCoffees
        let index = store.index
        var result: [CoffeeListSection] = []
        var currentHeader: String?
        var currentCoffees: [Coffee] = []

        for coffee in coffees {
            let header = store.sort.sectionLabel(
                for: coffee,
                priceWidthCents: index.priceWidthCents,
                pricePer100gWidthCents: index.pricePer100gWidthCents
            )
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
