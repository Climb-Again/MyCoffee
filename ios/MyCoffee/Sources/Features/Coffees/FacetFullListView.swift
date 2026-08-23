import SwiftUI

/// The `.searchable` full-value list behind "Show all (N) ›" — mandatory for
/// Roaster (~100 values) and Farm (hundreds), available for any dimension
/// past 8 entries (PLAN.md §6.2).
struct FacetFullListView: View {
    let dimension: FilterDimension
    let entries: [FacetCounts.Entry]
    let vocabulary: Vocabulary
    @Binding var draft: CoffeeFilter

    @State private var query = ""

    private var filtered: [FacetCounts.Entry] {
        guard !query.isEmpty else { return entries }
        let folded = query.foldedForSearch
        return entries.filter { facetLabel($0.key, dimension: dimension, vocabulary: vocabulary).foldedForSearch.contains(folded) }
    }

    var body: some View {
        List(filtered) { entry in
            FilterPill(
                title: facetLabel(entry.key, dimension: dimension, vocabulary: vocabulary),
                count: entry.count,
                averageRating: entry.averageRating,
                isSelected: isFacetSelected(entry.key, dimension: dimension, in: draft),
                isEnabled: isTappable(entry.key),
                isUnknown: { if case .unknown = entry.key { return true }; return false }(),
                action: { toggleFacet(entry.key, dimension: dimension, in: &draft) }
            )
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .searchable(text: $query)
        .navigationTitle(dimension.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isTappable(_ key: FacetKey) -> Bool {
        if case .unknown = key { return unknownSelectableDimensions.contains(dimension) }
        return true
    }
}
