import Foundation

/// A relative-to-today purchase-date window for the listing filter (#71) —
/// distinct from `CoffeeFilter.years`, which picks specific calendar years.
/// Mirrors `InsightsView.ChartWindow`'s `.last12m`/`.last18m` cases so a chart
/// tap can carry its window straight across (PLAN.md §13/#71(b)); `.all` and
/// `.years` have no counterpart here since `nil`/`years` already cover them.
enum RelativeWindow: CaseIterable, Hashable, Sendable {
    case last12m
    case last18m

    var months: Int {
        switch self {
        case .last12m: return 12
        case .last18m: return 18
        }
    }

    var label: String {
        switch self {
        case .last12m: return "Last 12 months"
        case .last18m: return "Last 18 months"
        }
    }

    /// The purchase-date cutoff for this window, evaluated against `now`
    /// (`Calendar.utc`, matching `InsightsView.coffeesSince(months:)`).
    func cutoff(now: Date = Date()) -> Date {
        Calendar.utc.date(byAdding: .month, value: -months, to: now) ?? .distantPast
    }
}
