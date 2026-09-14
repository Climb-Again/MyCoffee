import Foundation

/// #195 — one row of the browser extension's shortlist, as `GET /api/history`
/// returns it (#194).
///
/// The server stores the extension's payload **opaquely** (`history.payload`
/// jsonb): it only ever reads `url` to derive the dedupe key and stamps the
/// timestamps. So this DTO is a *subset* view of a shape the extension owns —
/// every field is optional except the url, and an unknown field is simply not
/// decoded rather than being an error. That is the same public-contract rule
/// CLAUDE.md §12 states from the other direction: the extension in someone's
/// browser and this app ship on completely different schedules, so neither may
/// require a field the other happens to send today.
struct ShortlistEntry: Identifiable, Decodable, Hashable, Sendable {
    let url: String
    let title: String?
    let roasterName: String?
    let originName: String?
    let pricePer100gEur: Double?
    let priceAmount: Double?
    let priceCurrency: String?
    let weightG: Int?
    let roastedOn: String?
    let imageUrl: String?
    /// The score the extension computed at the visit. The app renders this
    /// rather than recomputing: #199's re-blend needs the component scores and
    /// the extension's own weights, and two implementations of one number is
    /// exactly what that row's contract test exists to prevent.
    let score: Int?
    /// #196's manual ±10, already folded in by the extension when it displays.
    /// Kept separate here so the app can show the badge too.
    let adjustment: Int?
    /// Set once on first add (#197); retention is 30 days from this, not from
    /// the last visit.
    let addedAt: Double?
    let savedAt: Double?

    /// Same rule as the extension's `historyKey`: origin + path, so a revisit
    /// with different tracking params is the same row.
    var id: String { url }

    var displayScore: Int? {
        guard let score else { return nil }
        return max(0, min(100, score + (adjustment ?? 0)))
    }

    var addedDate: Date? { addedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var savedDate: Date? { savedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}
