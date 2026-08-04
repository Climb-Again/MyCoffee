import Foundation

/// A field the extraction pipeline couldn't decide alone (PLAN.md §1/§2) and
/// that a human now has to. Mirrors one `review_items` row (backend's
/// `routes/review.js`): `coffeeId` is intentionally optional — a photo can
/// have open review items before it's even resolved into a visible `Coffee`
/// row (the route's own `LEFT JOIN coffees`), so the card has to work from
/// the photo/snippet alone when it's nil.
struct ReviewTask: Identifiable, Hashable {
    let id: Int
    let coffeeId: String?
    let photoId: String
    let field: ReviewField
    /// The raw string under question, e.g. `"Etiopia"` — what batch cards
    /// group on alongside `field` (PLAN.md §6.5).
    let rawValue: String
    /// Why this landed in the queue, e.g. "low confidence (0.42)" or "range
    /// span 900 m" — shown as a small caption, never a bare "N/A".
    let reason: String?
    /// The fuller raw OCR text `rawValue` was pulled from, if any.
    let rawSnippet: String?
    /// Correction options, top pick first.
    let candidates: [ReviewCandidate]
    let createdAt: Date
}

struct ReviewCandidate: Identifiable, Hashable {
    var id: String { value }
    let value: String
    /// e.g. "3 other coffees" — set on alternates, nil on the top pick.
    let hint: String?
}

/// The field taxonomy a review task can name. Only the four with a
/// non-nil `aliasKind` persist as a reusable rule server-side
/// (`POST /api/review/rules`) — the backend's `ALIAS_TABLES` only covers
/// roaster/country/farm (`backend/src/routes/review.js`), so long-pressing a
/// profile/altitude/weight/price chip just accepts, it doesn't also offer
/// "and remember this for every future import."
enum ReviewField: String, CaseIterable, Hashable {
    case originCountry, roasterCountry, roaster, farm, profile, altitude, weight, price

    var label: String {
        switch self {
        case .originCountry: return "Origin country"
        case .roasterCountry: return "Roaster country"
        case .roaster: return "Roaster"
        case .farm: return "Farm"
        case .profile: return "Process"
        case .altitude: return "Altitude"
        case .weight: return "Weight"
        case .price: return "Price"
        }
    }

    var symbol: String {
        switch self {
        case .originCountry, .roasterCountry: return Symbols.reviewCountry
        case .roaster: return Symbols.reviewRoaster
        case .farm: return Symbols.reviewFarm
        case .profile: return Symbols.processUnknown
        case .altitude: return Symbols.mountain
        case .weight: return Symbols.scale
        case .price: return Symbols.eurosign
        }
    }

    var aliasKind: String? {
        switch self {
        case .originCountry, .roasterCountry: return "country"
        case .roaster: return "roaster"
        case .farm: return "farm"
        default: return nil
        }
    }
}

/// One created-and-remembered mapping rule (PLAN.md §6.5's long-press
/// gesture / `POST /api/review/rules`). Kept as a local, session-visible
/// record — see `ReviewQueueEngine`'s doc comment for why this doesn't POST
/// anywhere yet.
struct ReviewRule: Identifiable, Hashable {
    let id = UUID()
    let kind: String
    let rawValue: String
    let canonicalValue: String
    let appliedCount: Int
}

/// Tasks sharing `(field, rawValue)` across ≥8 photos collapse into one card
/// (PLAN.md §6.5): *"23 coffees say Etiopia → Ethiopia?"*.
struct ReviewBatchGroup: Identifiable {
    var id: String { "\(field.rawValue)|\(rawValue.reviewGroupingKey)" }
    let field: ReviewField
    let rawValue: String
    let topCandidate: ReviewCandidate
    let tasks: [ReviewTask]
}

/// The queue's actual display order: batch cards first, then individual
/// tasks (PLAN.md §6.5).
enum ReviewQueueEntry: Identifiable {
    case batch(ReviewBatchGroup)
    case single(ReviewTask)

    var id: String {
        switch self {
        case let .batch(group): return "batch-\(group.id)"
        case let .single(task): return "single-\(task.id)"
        }
    }
}

extension String {
    /// Case/diacritic/whitespace-insensitive key for batch grouping — not the
    /// same extension as the listing's search-fold (`Query`, shell-owned);
    /// kept local and separately named to avoid any risk of colliding with it.
    var reviewGroupingKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
