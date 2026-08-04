import Foundation

/// Signed, ready-to-use image URLs for one coffee's photo, as delivered by the
/// snapshot — the client never constructs these itself (the HMAC signing key
/// is server-only), it just uses them and refetches on the next sync before
/// `exp` passes. See PLAN.md §3.
struct CoffeeImageURLs: Codable, Hashable, Sendable {
    let thumb: String
    let display: String
    let ocr: String?             // nil until the review lane (#27) needs it; the detail route doesn't send one today
}

/// Mirrors the `coffees` row shape from PLAN.md §1. One row per bag; `photos`
/// is the ingest unit this is derived from, but the app only ever sees the
/// derived, reviewed record.
///
/// Property names deliberately spell out acronyms as `Id`/`Eur`, not `ID`/`EUR`:
/// `JSONDecoder.coffeeAPI` uses `.convertFromSnakeCase`, which turns
/// `roaster_id` into `roasterId` and `price_eur` into `priceEur` — never the
/// all-caps form — so matching that exactly is what makes decoding work
/// without a parallel `CodingKeys` enum (which would itself fight
/// `.convertFromSnakeCase`, since it compares against the *already-converted*
/// key, not the original).
struct Coffee: Identifiable, Codable, Hashable, Sendable {
    let id: String                          // public id, not the DB serial

    let purchasedOn: PlainDate

    // Optional: a coffee exists before its roaster is resolved/confirmed, so the
    // compact snapshot legitimately sends `roasterId: null`. Decoding it as a
    // required Int threw on every such row and — because the snapshot decodes the
    // coffees array all-or-nothing — dropped ALL coffees, leaving the shell empty.
    let roasterId: Int?
    let roasterCountryId: Int?

    let originCountryIds: [Int]
    let originCountryId: Int?                // generated display/primary value
    let isBlend: Bool

    let originFarmId: Int?

    let altitudeMinM: Int?
    let altitudeMaxM: Int?

    let profile: Profile?
    let profileDetail: String?
    let isDecaf: Bool

    let roastedOn: PlainDate?

    let priceOriginalAmount: Double?
    let priceOriginalCurrency: String?
    let priceEur: Double?
    let fxRate: Double?
    let fxRatePeriod: String?

    let weightG: Int?

    let rating: Double?
    let isFavorite: Bool
    let favoriteSetBy: String?               // "human" | "system"; nil if never set

    let farmLotNote: String?
    let brewGuideNote: String?
    let roasterCopyNote: String?

    let rawTitle: String?
    let rawCaption: String?
    let rawDescription: String?

    let reviewState: String                  // "clean" | "needs_review" — coarse, per-field detail lives server-side
    let minFieldConfidence: Double?

    let images: CoffeeImageURLs?

    var purchasedYear: Int { purchasedOn.year }
    var purchasedMonth: Int { purchasedOn.month }

    var altitudeMidM: Int? {
        switch (altitudeMinM, altitudeMaxM) {
        case let (.some(lo), .some(hi)): return (lo + hi) / 2
        case let (.some(lo), nil): return lo
        case let (nil, .some(hi)): return hi
        case (nil, nil): return nil
        }
    }

    /// Generated `price_per_100g_eur` — nil unless both price and weight are known.
    var pricePer100gEur: Double? {
        guard let priceEur, let weightG, weightG > 0 else { return nil }
        return priceEur / Double(weightG) * 100
    }

    var hasOpenReview: Bool { reviewState != "clean" }

    /// A copy with `isFavorite` flipped — `Coffee` stays a fully immutable
    /// value type (every field `let`) so it's trivially `Sendable` across the
    /// actor boundaries the sync engine and outbox cross; this is how
    /// `CoffeeStore.toggleFavorite` and `SyncEngine`'s "pending mutation wins"
    /// rule (PLAN.md §5) both apply an optimistic edit without widening any
    /// field to `var`.
    func withFavorite(_ isFavorite: Bool, setBy: String) -> Coffee {
        Coffee(
            id: id, purchasedOn: purchasedOn, roasterId: roasterId, roasterCountryId: roasterCountryId,
            originCountryIds: originCountryIds, originCountryId: originCountryId, isBlend: isBlend,
            originFarmId: originFarmId, altitudeMinM: altitudeMinM, altitudeMaxM: altitudeMaxM,
            profile: profile, profileDetail: profileDetail, isDecaf: isDecaf, roastedOn: roastedOn,
            priceOriginalAmount: priceOriginalAmount, priceOriginalCurrency: priceOriginalCurrency,
            priceEur: priceEur, fxRate: fxRate, fxRatePeriod: fxRatePeriod, weightG: weightG,
            rating: rating, isFavorite: isFavorite, favoriteSetBy: setBy,
            farmLotNote: farmLotNote, brewGuideNote: brewGuideNote, roasterCopyNote: roasterCopyNote,
            rawTitle: rawTitle, rawCaption: rawCaption, rawDescription: rawDescription,
            reviewState: reviewState, minFieldConfidence: minFieldConfidence, images: images
        )
    }
}
