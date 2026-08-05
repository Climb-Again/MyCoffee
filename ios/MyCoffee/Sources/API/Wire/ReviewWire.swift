import Foundation

/// Wire shapes for `GET /api/review` (backend `routes/review.js`). The backend
/// already maps each DB field onto the app's `ReviewField` raw value and
/// cleans the candidate list (dropping prose-span objects and whole-caption
/// dumps), so the client just decodes strings — the `ReviewTask` mapping lives
/// in `Features/Review/ReviewModels.swift`.
struct ReviewFeedDTO: Decodable {
    let total: Int
    let items: [ReviewItemDTO]

    private enum CodingKeys: String, CodingKey { case total, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        // Lenient: one malformed review row is skipped, never fatal to the
        // whole queue — same all-or-nothing guard the snapshot uses.
        items = try c.decode([FailableDecodable<ReviewItemDTO>].self, forKey: .items).compactMap(\.value)
    }
}

struct ReviewItemDTO: Decodable {
    let id: String                    // review_items.id — pg bigint, arrives as a JSON string
    let coffeeId: String?
    let photoId: String
    let field: String                 // already a `ReviewField` raw value
    let reason: String?
    let candidates: [ReviewCandidateDTO]
    let rawTitle: String?
    let rawCaption: String?
    let rawDescription: String?
    let thumbUrl: String?
    let createdAt: Date
}

struct ReviewCandidateDTO: Decodable {
    let value: String
    let hint: String?
}
