import SwiftUI

/// The Coffees tab: 2a-redesign blue header field, review nudge, filter chip
/// row (replacing `TopFilterCardsRow`), filter-state line, quiet month
/// headers, listing with sticky section headers, filter sheet, sort menu, and
/// navigation into detail (`#86`, `design/coffees_redesign/README.md`
/// §Screen 1). `List` + `.listStyle(.plain)` gives sticky headers and real
/// cell reuse for free — not `ScrollView` + `LazyVStack`.
///
/// **Redesign v2 §A** (`#93`, `design/coffees_redesign/UPDATE_BRIEF.md`):
/// the header and search field are lifted **out of the `List`** into a fixed
/// `VStack` above it. Round 1 painted the nav bar blue *and* put a blue
/// header row inside the `List` — the header scrolled away but the
/// now-titleless nav bar's blue toolbar background stayed, leaving an empty
/// blue band pinned at the top. Hiding the nav bar entirely and making the
/// header a real, non-scrolling sibling of the `List` removes the second band
/// by construction rather than by tuning it away.
struct CoffeesListView: View {
    @EnvironmentObject private var store: CoffeeStore

    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var showReviewQueue = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                searchField

                List {
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
                                CoffeeLink(coffee: coffee) {
                                    CoffeeRowView(coffee: coffee, vocabulary: store.index.vocabulary)
                                }
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
                // #100: the 2a design assumes a `surface` ground everywhere. Without
                // these two lines the system supplies its own background — black in
                // dark mode — under adaptive ink, which is the black-on-black bug.
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.surface)
                .refreshable {
                    await store.refresh()
                }
            }
            .background(Theme.Colors.surface)
            // §A1: one header band, no native nav bar underneath it at all —
            // the previous `.toolbarBackground(...)` pair plus an
            // inline-but-empty title is exactly what left a second blue band
            // behind after the in-`List` header scrolled away.
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Header

    private var headerStats: String {
        let bagCount = store.index.coffees.count
        let roasterCount = Set(store.index.coffees.compactMap(\.roasterId)).count
        return "\(bagCount) BAGS · \(roasterCount) ROASTERS"
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerStats)
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.accent200)
                Text("Coffees")
                    .font(.system(size: 30, weight: Theme.Weight.heavy))
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
                // §A5: sort + settings fold into one overflow menu rather than
                // a third ringed button on the header band.
                Menu {
                    Picker("Sort", selection: $store.sort) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: Symbols.settings)
                    }
                } label: {
                    headerIcon(Symbols.settings)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // §A1: the blue extends under the status bar; the `VStack` itself
        // isn't ignoring the safe area, so its content still lands below it —
        // one continuous band, not a second one layered under the nav bar.
        .background(Theme.Colors.accent.ignoresSafeArea(edges: .top))
    }

    // §A5: no ring — a plain glyph on the blue band.
    private func headerIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20))
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    // MARK: - Search

    /// §A2: a plain white pill under the header — not `.searchable`, which
    /// docks translucent-on-blue above the title and can't be restyled via
    /// public API.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: Symbols.search)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.neutral700)
            TextField("Search coffees, roasters, farms", text: $store.filter.query)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Capsule().fill(Theme.Colors.neutral100))
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface)
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
            // §A4: opaque so a sticky header never prints over the row it's
            // covering while scrolling. DEVIATION: the brief says
            // `Color.white` literally, written before #100 shipped adaptive
            // dark-mode tokens; `surface` is the same white in light mode and
            // avoids re-introducing a literal-on-token dark-mode bug.
            .background(Theme.Colors.surface)
            .listRowInsets(EdgeInsets())
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
