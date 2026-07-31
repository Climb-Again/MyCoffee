import Foundation

/// One of the ≤7 cards above the listing (PLAN.md §6.1). Built by
/// `CoffeeIndex.topFilterCards(limit:)`, which owns the selection and
/// gating rules; this type is just the resulting, ready-to-render value.
struct TopFilterCard: Identifiable, Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case favorites
        case highlyRated              // 4.5+
        case process(Profile)
        case originCountry(id: Int)
    }

    let kind: Kind
    let title: String
    let count: Int

    var id: String {
        switch kind {
        case .favorites: return "favorites"
        case .highlyRated: return "highlyRated"
        case .process(let profile): return "process-\(profile.rawValue)"
        case .originCountry(let id): return "originCountry-\(id)"
        }
    }

    /// Tapping a card fully replaces the current filter.
    var filter: CoffeeFilter { .replacing(with: kind) }
}
