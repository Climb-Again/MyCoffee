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
    /// Signed thumbnail of the source photo, if the backend sent one.
    let thumbUrl: String?
    /// The full scraped title/caption/description — the whole source context
    /// the extracted values came from, shown on demand under the card.
    let rawTitle: String?
    let rawCaption: String?
    let rawDescription: String?

    /// The four raw/thumb fields default to nil so the sample-data fixtures
    /// (`ReviewSampleData`) — written before the real feed carried them — keep
    /// compiling unchanged; the real feed populates them via `init(dto:)`.
    init(
        id: Int, coffeeId: String?, photoId: String, field: ReviewField,
        rawValue: String, reason: String?, rawSnippet: String?,
        candidates: [ReviewCandidate], createdAt: Date,
        thumbUrl: String? = nil, rawTitle: String? = nil,
        rawCaption: String? = nil, rawDescription: String? = nil
    ) {
        self.id = id
        self.coffeeId = coffeeId
        self.photoId = photoId
        self.field = field
        self.rawValue = rawValue
        self.reason = reason
        self.rawSnippet = rawSnippet
        self.candidates = candidates
        self.createdAt = createdAt
        self.thumbUrl = thumbUrl
        self.rawTitle = rawTitle
        self.rawCaption = rawCaption
        self.rawDescription = rawDescription
    }

    /// The fullest available source text — what the "Full text" disclosure on
    /// the review card shows so the reviewer can decide from the whole caption.
    var fullText: String? {
        for candidate in [rawDescription, rawCaption, rawTitle] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    /// Maps one `GET /api/review` row onto a task. Returns nil for a row whose
    /// id doesn't parse or whose `field` this build's `ReviewField` doesn't
    /// know (the backend already filters to reviewable fields, but staying
    /// defensive means a vocabulary the app predates just drops one card).
    init?(dto: ReviewItemDTO) {
        guard let id = Int(dto.id), let field = ReviewField(rawValue: dto.field) else { return nil }
        let candidates = dto.candidates.map { ReviewCandidate(value: $0.value, hint: $0.hint) }
        self.init(
            id: id,
            coffeeId: dto.coffeeId,
            photoId: dto.photoId,
            field: field,
            // Batch grouping + snippet highlight anchor on the top candidate.
            rawValue: candidates.first?.value ?? "",
            reason: dto.reason,
            rawSnippet: dto.rawCaption ?? dto.rawTitle ?? dto.rawDescription,
            candidates: candidates,
            createdAt: dto.createdAt,
            thumbUrl: dto.thumbUrl,
            rawTitle: dto.rawTitle,
            rawCaption: dto.rawCaption,
            rawDescription: dto.rawDescription
        )
    }
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
