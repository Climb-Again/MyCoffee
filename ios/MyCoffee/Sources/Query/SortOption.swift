import Foundation

/// Listing sort orders (PLAN.md §6.1). Each has its own section-header rule;
/// nil values always sort last and get the table's "trailing" section rather
/// than being dropped.
enum SortOption: CaseIterable, Sendable {
    case dateBought
    case rating
    case price
    case pricePer100g

    /// Canonical descending order — most recent / highest first, nils last.
    func isOrderedBefore(_ lhs: Coffee, _ rhs: Coffee) -> Bool {
        switch self {
        case .dateBought:
            return rhs.purchasedOn < lhs.purchasedOn
        case .rating:
            return orderedByOptional(lhs.rating, rhs.rating)
        case .price:
            return orderedByOptional(lhs.priceEur, rhs.priceEur)
        case .pricePer100g:
            return orderedByOptional(lhs.pricePer100gEur, rhs.pricePer100gEur)
        }
    }

    private func orderedByOptional(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(l), .some(r)): return l > r
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return false
        }
    }

    /// The section header a coffee falls under when the listing is sorted by
    /// this option. `priceWidthCents`/`pricePer100gWidthCents` come from
    /// `CoffeeIndex`, which computes one shared bucket width per dataset.
    func sectionLabel(for coffee: Coffee, priceWidthCents: Int?, pricePer100gWidthCents: Int?) -> String {
        switch self {
        case .dateBought:
            return Self.monthYearFormatter.string(from: coffee.purchasedOn.utcMidnight)
        case .rating:
            return RatingBand.band(for: coffee.rating).label
        case .price:
            guard let priceEur = coffee.priceEur, let width = priceWidthCents else { return "No price" }
            return PriceBand.band(forEUR: priceEur, widthCents: width).label
        case .pricePer100g:
            guard let ppg = coffee.pricePer100gEur, let width = pricePer100gWidthCents else { return "No price" }
            return PriceBand.band(forEUR: ppg, widthCents: width).label + " / 100 g"
        }
    }

    /// When *not* sorted by date, the row footer falls back to month-year so
    /// the brief's required date is never lost (PLAN.md §6.1).
    static func monthYearLabel(for coffee: Coffee) -> String {
        monthYearFormatter.string(from: coffee.purchasedOn.utcMidnight)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.utc
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "LLLL yyyy"
        return f
    }()
}
