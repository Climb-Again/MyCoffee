import Foundation

/// Half-open `[lower, upper)` rating buckets, per PLAN.md §5. `5.0` folds into
/// the top band rather than getting its own; `.under3` and `.unrated` are
/// shown only when non-empty (a listing filter/section-header concern, not
/// enforced here).
enum RatingBand: CaseIterable, Hashable, Sendable {
    case under3
    case threeToThreeFive
    case threeFiveToFour
    case fourToFourFive
    case fourFiveToFive
    case unrated

    var label: String {
        switch self {
        case .under3: return "Under 3 ★"
        case .threeToThreeFive: return "3.0 – 3.5 ★"
        case .threeFiveToFour: return "3.5 – 4.0 ★"
        case .fourToFourFive: return "4.0 – 4.5 ★"
        case .fourFiveToFive: return "4.5 – 5.0 ★"
        case .unrated: return "Unrated"
        }
    }

    static func band(for rating: Double?) -> RatingBand {
        guard let rating else { return .unrated }
        switch rating {
        case ..<3: return .under3
        case 3..<3.5: return .threeToThreeFive
        case 3.5..<4: return .threeFiveToFour
        case 4..<4.5: return .fourToFourFive
        default: return .fourFiveToFive          // covers [4.5, 5.0], folding 5.0 in
        }
    }
}
