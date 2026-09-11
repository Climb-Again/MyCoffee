import Foundation

/// View-free data shaping for the Insights charts and the Data quality card
/// (PLAN.md §6.4). No statistics here — see `InsightsStats` for the gated
/// correlations; this file only groups and counts.
enum InsightsAggregation {
    struct DataQualityField: Identifiable {
        let label: String
        let missing: Int
        let total: Int
        /// The filter dimension whose "Unknown" facet this field's missing
        /// count corresponds to — `nil` when the field isn't a listing facet
        /// at all (e.g. weight), per PLAN.md §13/#54: only fields with a real
        /// Unknown bucket in `CoffeeFilter` are tappable.
        let dimension: FilterDimension?
        var id: String { label }
    }

    /// Field-completeness rows for the Data quality card — one of the "two
    /// additions the brief doesn't ask for but should have" (PLAN.md §6.4).
    /// Only fields present today on `Coffee` and plausibly missing on a real
    /// bag are counted; fields always present by construction (`id`,
    /// `purchasedOn`) aren't listed. Rows with zero missing are omitted —
    /// a 100%-complete field isn't a data-quality concern.
    static func dataQuality(coffees: [Coffee]) -> [DataQualityField] {
        let total = coffees.count
        guard total > 0 else { return [] }
        func missingCount(_ predicate: (Coffee) -> Bool) -> Int { coffees.filter(predicate).count }

        return [
            DataQualityField(label: "Rating", missing: missingCount { $0.rating == nil }, total: total, dimension: .ratingBand),
            DataQualityField(label: "Process", missing: missingCount { $0.profile == nil }, total: total, dimension: .profile),
            DataQualityField(label: "Origin country", missing: missingCount { $0.originCountryId == nil && !$0.isBlend }, total: total, dimension: .originCountry),
            DataQualityField(label: "Roaster country", missing: missingCount { $0.roasterCountryId == nil }, total: total, dimension: .roasterCountry),
            DataQualityField(label: "Altitude", missing: missingCount { $0.altitudeMinM == nil && $0.altitudeMaxM == nil }, total: total, dimension: .altitudeBand),
            DataQualityField(label: "Price", missing: missingCount { $0.priceEur == nil }, total: total, dimension: .priceBand),
            // Weight has no corresponding `FilterDimension` — not a listing facet — so stays non-interactive.
            DataQualityField(label: "Weight", missing: missingCount { $0.weightG == nil }, total: total, dimension: nil),
        ]
        .filter { $0.missing > 0 }
        .sorted { $0.missing > $1.missing }
    }
}
