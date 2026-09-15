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
    private(set) var id: String                          // public id, not the DB serial

    /// Optional (#211): nullable server-side (`008_coffees.sql:26`). Widened
    /// from non-optional so `CompactCoffeeDTO.makeCoffee` no longer has to
    /// drop the whole coffee to satisfy this one field (#178(b)) — see that
    /// function's history for what the old failable path cost.
    private(set) var purchasedOn: PlainDate?

    // Optional: a coffee exists before its roaster is resolved/confirmed, so the
    // compact snapshot legitimately sends `roasterId: null`. Decoding it as a
    // required Int threw on every such row and — because the snapshot decodes the
    // coffees array all-or-nothing — dropped ALL coffees, leaving the shell empty.
    private(set) var roasterId: Int?
    private(set) var roasterCountryId: Int?

    private(set) var originCountryIds: [Int]
    private(set) var originCountryId: Int?                // generated display/primary value
    private(set) var isBlend: Bool

    private(set) var originFarmId: Int?

    private(set) var altitudeMinM: Int?
    private(set) var altitudeMaxM: Int?

    private(set) var profile: Profile?
    private(set) var profileDetail: String?
    private(set) var isDecaf: Bool

    private(set) var roastedOn: PlainDate?

    private(set) var priceOriginalAmount: Double?
    private(set) var priceOriginalCurrency: String?
    private(set) var priceEur: Double?
    private(set) var fxRate: Double?
    private(set) var fxRatePeriod: String?

    private(set) var weightG: Int?

    private(set) var rating: Double?
    private(set) var isFavorite: Bool
    private(set) var favoriteSetBy: String?               // "human" | "system"; nil if never set

    private(set) var farmLotNote: String?
    private(set) var brewGuideNote: String?
    private(set) var roasterCopyNote: String?

    /// Short comma-separated tasting notes (#79/#81), e.g. "dark chocolate,
    /// cherry, dried plum". Detail-only — the compact snapshot omits it to
    /// spare its per-row budget, so this is nil until a detail fetch supplies
    /// it (same pattern as `farmLotNote`/`rawTitle`). `nil` and `""` both mean
    /// "none yet"; the view shows the section only when non-empty.
    private(set) var flavorNotes: String?

    private(set) var rawTitle: String?
    private(set) var rawCaption: String?
    private(set) var rawDescription: String?

    private(set) var reviewState: String                  // "clean" | "needs_review" — coarse, per-field detail lives server-side
    private(set) var minFieldConfidence: Double?

    /// Persisted display rotation (#57/#73): quarter-turns clockwise the app
    /// applies when showing the photo. Optional so an older on-disk cache
    /// (PersistedSnapshot Codable-decodes `[Coffee]` directly) that predates
    /// the field decodes as nil instead of dropping the whole cache; treat nil
    /// as 0 (`rotationTurns`).
    private(set) var rotationQuarterTurns: Int?

    private(set) var images: CoffeeImageURLs?

    /// Brew lab (PLAN.md §14, #155/#156): every `BrewOption.id` this coffee has
    /// tried / marked best, by kind. Optional, same reasoning as
    /// `rotationQuarterTurns` — an older on-disk `PersistedSnapshot` and a
    /// compact/detail row with no trials both omit the key entirely, and
    /// decoding that as a required `[Int]` would drop the whole coffee (or the
    /// whole snapshot) rather than just reading as "nothing tried yet".
    private(set) var brewTriedIds: [Int]?
    private(set) var brewBestIds: [Int]?

    /// nil-safe view of `rotationQuarterTurns`, normalized to 0–3.
    var rotationTurns: Int { ((rotationQuarterTurns ?? 0) % 4 + 4) % 4 }

    /// nil-safe views of `brewTriedIds`/`brewBestIds` — every call site should
    /// read through these rather than the raw optionals.
    var triedBrewOptionIds: [Int] { brewTriedIds ?? [] }
    var bestBrewOptionIds: [Int] { brewBestIds ?? [] }

    var purchasedYear: Int? { purchasedOn?.year }
    var purchasedMonth: Int? { purchasedOn?.month }

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

    /// A client-synthesized stand-in for a coffee the backend has just
    /// created but not yet extracted (#118/#130's `quick-create` flow) —
    /// every field but `id`/`reviewState`/`purchasedOn` is empty/nil, since
    /// nothing else is known yet. `purchasedOn` is today: the backend sets
    /// `purchased_on` from the primary photo's `captured_at`, which the
    /// wizard's own upload step also stamps as "now" (`SyncEngine.uploadPhotos`),
    /// so this matches what the server actually recorded. Superseded field by
    /// field by the next normal delta sync once the backend's background
    /// extraction pass finishes and flips `reviewState` off `"unextracted"`.
    static func pendingPlaceholder(id: String, reviewState: String) -> Coffee {
        Coffee(
            id: id, purchasedOn: PlainDate(utcToday: Date()), roasterId: nil, roasterCountryId: nil,
            originCountryIds: [], originCountryId: nil, isBlend: false,
            originFarmId: nil, altitudeMinM: nil, altitudeMaxM: nil,
            profile: nil, profileDetail: nil, isDecaf: false, roastedOn: nil,
            priceOriginalAmount: nil, priceOriginalCurrency: nil, priceEur: nil, fxRate: nil, fxRatePeriod: nil,
            weightG: nil, rating: nil, isFavorite: false, favoriteSetBy: nil,
            farmLotNote: nil, brewGuideNote: nil, roasterCopyNote: nil, flavorNotes: nil,
            rawTitle: nil, rawCaption: nil, rawDescription: nil,
            reviewState: reviewState, minFieldConfidence: nil,
            rotationQuarterTurns: nil, images: nil,
            brewTriedIds: nil, brewBestIds: nil
        )
    }

    /// One copier instead of three 35-argument ones.
    ///
    /// `withFavorite`/`withRotation`/`withBrew` each used to spell out all 35
    /// initialiser arguments, so adding a field meant editing three unrelated
    /// functions and any one of them silently dropping the new field was a
    /// compile-clean bug. They now share this.
    ///
    /// The properties are `private(set) var`, so `Coffee` is still immutable to
    /// everyone outside this file — the only mutators are the three named ones
    /// below. (The old doc comment justified all-`let` as what made `Coffee`
    /// `Sendable`; that was never the reason. A struct is `Sendable` when its
    /// stored properties are, `let` or `var`.)
    private func with(_ mutate: (inout Coffee) -> Void) -> Coffee {
        var copy = self
        mutate(&copy)
        return copy
    }

    /// A copy with `isFavorite` flipped — how `CoffeeStore.toggleFavorite` and
    /// `SyncEngine`'s "pending mutation wins" rule (PLAN.md §5) both apply an
    /// optimistic edit.
    func withFavorite(_ isFavorite: Bool, setBy: String) -> Coffee {
        with {
            $0.isFavorite = isFavorite
            $0.favoriteSetBy = setBy
        }
    }

    /// A copy with the display rotation set (#57) — same optimistic-update
    /// pattern, so the store reflects a rotate the moment the user taps.
    func withRotation(_ turns: Int) -> Coffee {
        with { $0.rotationQuarterTurns = ((turns % 4) + 4) % 4 }
    }

    /// A copy with the brew lab's tried/best id sets replaced (PLAN.md §14).
    /// `SyncEngine` is the only caller: it computes the new sets (locally for
    /// an optimistic tap, or from the server's whole-state response after a
    /// flush) and passes them straight through.
    func withBrew(tried: [Int], best: [Int]) -> Coffee {
        with {
            $0.brewTriedIds = tried
            $0.brewBestIds = best
        }
    }
}
