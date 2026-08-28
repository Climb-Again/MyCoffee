import SwiftUI

/// The Coffees tab: 2a-redesign blue header field, review nudge, filter chip
/// row (replacing `TopFilterCardsRow`), filter-state line, quiet month
/// headers, `.searchable` listing with sticky section headers, filter sheet,
/// sort menu, and navigation into detail (`#86`,
/// `design/coffees_redesign/README.md` §Screen 1). `List` +
/// `.listStyle(.plain)` gives sticky headers and real cell reuse for free —
/// not `ScrollView` + `LazyVStack`.
struct CoffeesListView: View {
    @EnvironmentObject private var store: CoffeeStore

    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var showReviewQueue = false

    var body: some View {
        NavigationStack {
            List {
                headerSection

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
                            NavigationLink(value: coffee.id) {
                                CoffeeRowView(coffee: coffee, vocabulary: store.index.vocabulary)
                            }
                        }
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
            // #100: the 2a design assumes a `surface` ground everywhere. Without
            // these two lines the system supplies its own background — black in
            // dark mode — under adaptive ink, which is the black-on-black bug.
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.surface)
            // Placement itself is set by `RootTabView`'s `Tab(value:)` builder
            // (#58) — on iOS 26 that docks this field near the bottom tab bar
            // instead of the top nav bar; the binding/prompt are unchanged.
            // The system search chrome's fill/radius is not independently
            // stylable via public API, so the "pill search field" token from
            // the handoff isn't applied here — same system-behaviour carve-out
            // #58 already took for its placement.
            .searchable(text: $store.filter.query, prompt: "Search coffees, roasters, farms")
            // The custom `headerSection` row carries the "Coffees" title and
            // the filter/sort/settings actions now, so the native nav bar
            // itself is reduced to an inline, colour-matched strip rather than
            // hidden outright — hiding it entirely risked interacting badly
            // with #58's iOS 26 `.searchable` bottom-docking, which is keyed
            // off the tab's own `Tab(value:)` builder, not this view's bar.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.accent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { coffeeID in
                if let coffee = store.index.coffee(id: coffeeID) {
                    CoffeeDetailView(coffee: coffee)
                }
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
            .refreshable {
                await store.refresh()
            }
        }
    }

    // MARK: - Header

    private var headerStats: String {
        let bagCount = store.index.coffees.count
        let roasterCount = Set(store.index.coffees.compactMap(\.roasterId)).count
        return "\(bagCount) BAGS · \(roasterCount) ROASTERS"
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerStats)
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.accent200)
                Text("Coffees")
                    .font(.system(size: 36, weight: Theme.Weight.heavy))
                    .tracking(-1.08)
                    .foregroundStyle(Theme.Colors.onAccent)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button {
                    showFilterSheet = true
                } label: {
                    headerIcon(store.filter.isEmpty ? Symbols.filter : Symbols.filterFilled)
                }
                Menu {
                    Picker("Sort", selection: $store.sort) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    headerIcon(Symbols.sort)
                }
                Button {
                    showSettings = true
                } label: {
                    headerIcon(Symbols.settings)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accent)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func headerIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20))
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(width: 44, height: 44)
            .overlay(Circle().strokeBorder(Theme.Colors.onAccent, lineWidth: 1.6))
            .contentShape(Circle())
    }

    // MARK: - Review nudge

    private var reviewNudge: some View {
        Button {
            showReviewQueue = true
        } label: {
            HStack(spacing: 6) {
                Text("\(store.reviewQueueCount) bag\(store.reviewQueueCount == 1 ? "" : "s") need review")
                    .font(.system(size: 12, weight: Theme.Weight.semibold))
                Image(systemName: Symbols.chevronRight)
                    .font(.system(size: 11, weight: .semibold))
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

    // MARK: - Filter chips

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
            HStack(spacing: 6) {
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
            .background(Capsule().fill(isActive ? Theme.Colors.accent : Theme.Colors.surface))
            .overlay(Capsule().strokeBorder(isActive ? Theme.Colors.accent : Theme.Colors.neutral300, lineWidth: 1))
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

    // MARK: - Month headers

    private func monthHeader(_ title: String) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: Theme.Weight.semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.Colors.neutral700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }

    // MARK: - Sectioning

    private struct CoffeeListSection: Identifiable {
        let header: String
        let coffees: [Coffee]
        var id: String { header }
    }

    /// Coffees arrive from `CoffeeIndex.coffees(matching:sortedBy:)` already
    /// ordered, and every sort's section key is monotonic along that order,
    /// so a single contiguous-run pass is enough — no need to bucket into a
    /// dictionary and re-sort headers.
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
