import Foundation

/// The brief's five processing profiles. `is_decaf` is tracked separately on
/// `Coffee` — decaffeination is orthogonal to process, not a sixth case — and a
/// `nil` profile renders as an "Unknown" facet chip rather than defaulting to
/// the modal value (Washed).
enum Profile: String, Codable, CaseIterable, Sendable, Identifiable {
    case washed
    case natural
    case anaerobic
    case coFermented = "co_fermented"
    case experimental

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .washed: return "Washed"
        case .natural: return "Natural"
        case .anaerobic: return "Anaerobic"
        case .coFermented: return "Co-fermented"
        case .experimental: return "Experimental"
        }
    }

    /// Natural and Washed are ~70% of the library — not a useful "top filter" shortcut.
    var isInterestingForTopFilters: Bool {
        switch self {
        case .natural, .washed: return false
        case .anaerobic, .coFermented, .experimental: return true
        }
    }
}
