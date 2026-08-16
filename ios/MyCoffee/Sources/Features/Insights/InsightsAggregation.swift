import Foundation

/// View-free data shaping for the Insights charts and the Data quality card
/// (PLAN.md §6.4). No statistics here — see `InsightsStats` for the gated
/// correlations; this file only groups and counts.
enum InsightsAggregation {
    struct CategoryYearPoint: Identifiable {
        let year: Int
        let category: String
        let count: Int
        var id: String { "\(year)|\(category)" }
    }

    struct CategoryYearChartData {
        let points: [CategoryYearPoint]
        let categories: [String]     // stable legend/color order, "Other" last if present
    }

    /// A "top-N + Other" stacked-by-year series. `label` never returns `nil`
    /// — callers fold missing values into "Unknown" so a bar's total height
    /// always matches the year's actual coffee count, the same way the
    /// listing's own facet counts keep an explicit "Unknown" bucket rather
    /// than silently dropping rows.
    static func yearlyTopCategories(coffees: [Coffee], topN: Int, label: (Coffee) -> String) -> CategoryYearChartData {
        var totalByCategory: [String: Int] = [:]
        for coffee in coffees { totalByCategory[label(coffee), default: 0] += 1 }

        let ranked = totalByCategory.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        let topCategories = Set(ranked.prefix(topN).map(\.key))
        let hasOther = ranked.count > topN

        var countsByYearCategory: [Int: [String: Int]] = [:]
        for coffee in coffees {
            let raw = label(coffee)
            let category = topCategories.contains(raw) ? raw : "Other"
            countsByYearCategory[coffee.purchasedYear, default: [:]][category, default: 0] += 1
        }

        var points: [CategoryYearPoint] = []
        for (year, counts) in countsByYearCategory {
            for (category, count) in counts {
                points.append(CategoryYearPoint(year: year, category: category, count: count))
            }
        }

        var categories = ranked.prefix(topN).map(\.key)
        if hasOther { categories.append("Other") }
        return CategoryYearChartData(points: points.sorted { $0.year < $1.year }, categories: categories)
    }

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
