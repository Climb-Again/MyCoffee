import SwiftUI

/// The Coffees tab: top filter cards, `.searchable` listing with sticky
/// section headers, filter sheet, sort menu, and navigation into detail
/// (PLAN.md §6.1). `List` + `.listStyle(.plain)` gives sticky headers and
/// real cell reuse for free — not `ScrollView` + `LazyVStack`.
struct CoffeesListView: View {
    @EnvironmentObject private var store: CoffeeStore

    @State private var showFilterSheet = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            searchableList
                .navigationTitle("Coffees")
                .navigationDestination(for: String.self) { coffeeID in
                    if let coffee = store.index.coffee(id: coffeeID) {
                        CoffeeDetailView(coffee: coffee)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showFilterSheet = true
                        } label: {
                            Label("Filter", systemImage: store.filter.isEmpty ? Symbols.filter : Symbols.filterFilled)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort", selection: $store.sort) {
                                ForEach(SortOption.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: Symbols.sort)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: Symbols.settings)
                        }
                    }
                }
                .sheet(isPresented: $showFilterSheet) {
                    FilterSheetView(store: store)
                }
                .sheet(isPresented: $showSettings) {
                    SettingsSheet()
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

    /// The listing `List`, with search attached. iOS 26 anchors `.searchable`
    /// at the bottom (thumb-reach) when given `.tabBar` placement instead of
    /// the default nav-bar-top field — that placement case doesn't exist
    /// pre-26, so it's gated behind `#available` and falls back to today's
    /// top placement on 17–25. Same binding/prompt either way; this is
    /// placement only (PLAN.md's own framing of the row).
    @ViewBuilder
    private var searchableList: some View {
        let list = List {
            let cards = store.topFilterCards
            if !cards.isEmpty {
                Section {
                    TopFilterCardsRow(cards: cards, activeFilter: store.filter) { card in
                        store.filter = card.filter
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(sections) { section in
                Section(section.header) {
                    ForEach(section.coffees) { coffee in
                        NavigationLink(value: coffee.id) {
                            CoffeeRowView(coffee: coffee, vocabulary: store.index.vocabulary, sort: store.sort)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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

        if #available(iOS 26.0, *) {
            list.searchable(text: $store.filter.query, placement: .tabBar, prompt: "Search coffees, roasters, farms")
        } else {
            list.searchable(text: $store.filter.query, prompt: "Search coffees, roasters, farms")
        }
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
