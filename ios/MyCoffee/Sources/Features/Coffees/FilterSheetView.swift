import SwiftUI

/// The filter sheet (PLAN.md §6.2): `.presentationDetents([.large])`,
/// sections in `FilterDimension`'s declared order, `WrapLayout`-wrapped
/// pills truncated to the top 8 with a "Show all" drill-down, sticky
/// `✕ Clear` / `Show N coffees` footer.
struct FilterSheetView: View {
    @ObservedObject var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    /// Edited in place, applied only on "Show N coffees" — cancelling should
    /// leave the listing's active filter untouched.
    @State private var draft: CoffeeFilter

    init(store: CoffeeStore) {
        self.store = store
        _draft = State(initialValue: store.filter)
    }

    private var facets: FacetCounts { store.index.facets(for: draft) }
    private var matchCount: Int { store.index.matches(draft).count }

    var body: some View {
        NavigationStack {
            List {
                ForEach(FilterDimension.allCases, id: \.self) { dimension in
                    Section(dimension.title) {
                        switch dimension {
                        case .favorite:
                            FavoriteRow(isOn: $draft.favoritesOnly)
                        case .decaf:
                            let decafEntries = facets[.decaf]
                            DecafRow(
                                selection: $draft.isDecaf,
                                caffeinatedCount: decafEntries.first { $0.key == .bool(false) }?.count ?? 0,
                                decafCount: decafEntries.first { $0.key == .bool(true) }?.count ?? 0
                            )
                        default:
                            DimensionPills(
                                dimension: dimension,
                                entries: facets[dimension],
                                vocabulary: store.index.vocabulary,
                                draft: $draft
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("✕ Clear") {
                        draft = CoffeeFilter()
                    }
                    .disabled(draft.isEmpty)

                    Spacer()

                    Button("Show \(matchCount) coffees") {
                        store.filter = draft
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }
}

private struct FavoriteRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Favourites only", isOn: $isOn)
    }
}

private struct DecafRow: View {
    @Binding var selection: Bool?
    let caffeinatedCount: Int
    let decafCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Decaf", selection: Binding(
                get: { selection.map { $0 ? 1 : 0 } ?? -1 },
                set: { selection = $0 == -1 ? nil : $0 == 1 }
            )) {
                Text("Both").tag(-1)
                Text("Caffeinated").tag(0)
                Text("Decaf").tag(1)
            }
            .pickerStyle(.segmented)

            // Counter so the split is visible without applying the filter.
            Text("\(caffeinatedCount) caffeinated · \(decafCount) decaf")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The wrapped pill grid for one dimension, truncated to the top 8 with a
/// "Show all" push for the rest — mandatory for Roaster/Farm (PLAN.md §6.2).
private struct DimensionPills: View {
    let dimension: FilterDimension
    let entries: [FacetCounts.Entry]
    let vocabulary: Vocabulary
    @Binding var draft: CoffeeFilter

    private var visible: [FacetCounts.Entry] { Array(entries.prefix(8)) }
    private var needsFullList: Bool { dimension.alwaysNeedsFullList || entries.count > 8 }

    var body: some View {
        WrapLayout() {
            ForEach(visible) { entry in
                pill(for: entry)
            }
        }
        if needsFullList {
            NavigationLink {
                FacetFullListView(dimension: dimension, entries: entries, vocabulary: vocabulary, draft: $draft)
            } label: {
                Text("Show all (\(entries.count)) ›")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pill(for entry: FacetCounts.Entry) -> some View {
        let isUnknown: Bool = { if case .unknown = entry.key { return true }; return false }()
        return FilterPill(
            title: facetLabel(entry.key, dimension: dimension, vocabulary: vocabulary),
            count: entry.count,
            averageRating: entry.averageRating,
            isSelected: isSelected(entry.key),
            isEnabled: isTappable(entry.key),
            isUnknown: isUnknown,
            action: { toggle(entry.key) }
        )
    }

    private func isTappable(_ key: FacetKey) -> Bool {
        if case .unknown = key { return unknownSelectableDimensions.contains(dimension) }
        return true
    }

    private func isSelected(_ key: FacetKey) -> Bool {
        isFacetSelected(key, dimension: dimension, in: draft)
    }

    private func toggle(_ key: FacetKey) {
        toggleFacet(key, dimension: dimension, in: &draft)
    }
}

/// The "Unknown / missing" bucket is selectable on the vocab dimensions
/// (roaster, roaster country, origin, farm, profile) so you can filter to
/// coffees lacking that field — i.e. what still needs editing (#68). The band
/// dimensions don't carry an Unknown bucket, so it's shown-only there. Shared
/// between the truncated pill grid (`DimensionPills`) and the full searchable
/// list (`FacetFullListView`) so the two never drift apart on which
/// dimensions allow it.
let unknownSelectableDimensions: Set<FilterDimension> =
    [.roaster, .roasterCountry, .originCountry, .farm, .profile]

/// Whether a facet value is part of the active filter, given its dimension.
func isFacetSelected(_ key: FacetKey, dimension: FilterDimension, in filter: CoffeeFilter) -> Bool {
    switch (dimension, key) {
    case (.roaster, .vocabID(let id)): return filter.roasterIDs.contains(id)
    case (.roasterCountry, .vocabID(let id)): return filter.roasterCountryIDs.contains(id)
    case (.originCountry, .vocabID(let id)): return filter.originCountryIDs.contains(id)
    case (.farm, .vocabID(let id)): return filter.farmIDs.contains(id)
    case (.profile, .profile(let p)): return filter.profiles.contains(p)
    case (.ratingBand, .ratingBand(let b)): return filter.ratingBands.contains(b)
    case (.priceBand, .priceBand(let b)): return filter.priceBands.contains(b)
    case (.pricePer100gBand, .priceBand(let b)): return filter.pricePer100gBands.contains(b)
    case (.altitudeBand, .altitudeBand(let b)): return filter.altitudeBands.contains(b)
    case (.year, .year(let y)): return filter.years.contains(y)
    case (.decaf, .bool(let d)): return filter.isDecaf == d
    case (_, .unknown): return filter.unknownDimensions.contains(dimension)
    default: return false
    }
}

/// Toggles one facet value's membership on `filter`, given its dimension.
/// Shared between the truncated pill grid and the full searchable list.
func toggleFacet(_ key: FacetKey, dimension: FilterDimension, in filter: inout CoffeeFilter) {
    func flip<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if !set.insert(value).inserted { set.remove(value) }
    }

    switch (dimension, key) {
    case (.roaster, .vocabID(let id)): flip(&filter.roasterIDs, id)
    case (.roasterCountry, .vocabID(let id)): flip(&filter.roasterCountryIDs, id)
    case (.originCountry, .vocabID(let id)): flip(&filter.originCountryIDs, id)
    case (.farm, .vocabID(let id)): flip(&filter.farmIDs, id)
    case (.profile, .profile(let p)): flip(&filter.profiles, p)
    case (.ratingBand, .ratingBand(let b)): flip(&filter.ratingBands, b)
    case (.priceBand, .priceBand(let b)): flip(&filter.priceBands, b)
    case (.pricePer100gBand, .priceBand(let b)): flip(&filter.pricePer100gBands, b)
    case (.altitudeBand, .altitudeBand(let b)): flip(&filter.altitudeBands, b)
    case (.year, .year(let y)): flip(&filter.years, y)
    case (.decaf, .bool(let d)): filter.isDecaf = (filter.isDecaf == d) ? nil : d
    case (_, .unknown): flip(&filter.unknownDimensions, dimension)
    default: break
    }
}
