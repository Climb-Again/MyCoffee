import Foundation

/// Wire shapes for `GET /api/snapshot` (PLAN.md §4) — decoded once per sync
/// and mapped into the app's own `Coffee`/`Vocabulary` models
/// (`CoffeeMapping.swift`), never used directly outside `SyncEngine`.
struct SnapshotResponseDTO: Decodable {
    let version: Int
    let generatedAt: Date
    let vocab: VocabDTO
    let coffees: [CompactCoffeeDTO]
    let deleted: [String]

    private enum CodingKeys: String, CodingKey {
        case version, generatedAt, vocab, coffees, deleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        vocab = try c.decode(VocabDTO.self, forKey: .vocab)
        // Lenient: skip any coffee row that fails to decode rather than losing
        // the whole list. One malformed row must never blank the app again.
        //
        // #178(b): but it must not be SILENT either. Skipping is the right
        // trade; skipping without telling anyone means a coffee can vanish
        // from the library and look exactly like a coffee that was never
        // added. `SnapshotDecodeStats` records how many rows this dropped;
        // `CoffeeStore.droppedRowCount` publishes it and Settings shows it.
        let decoded = try c.decode([FailableDecodable<CompactCoffeeDTO>].self, forKey: .coffees)
        coffees = decoded.compactMap(\.value)
        SnapshotDecodeStats.shared.record(dropped: decoded.count - coffees.count)
        deleted = try c.decodeIfPresent([String].self, forKey: .deleted) ?? []
    }
}

struct SnapshotTextResponseDTO: Decodable {
    let texts: [String: String]
}

/// The backend's `loadVocabDictionary()` bundles raw DB rows from three
/// different loaders plus a plain `profiles` query — `countries`/`roasters`/
/// `farms` map onto the client's `Vocabulary` models (`Country` has its own
/// custom `Codable` to bridge its `iso2`/`kind` wire columns, see
/// `Models/Vocab.swift`); `profiles` has no client-side model of its own
/// because `Profile` is a fixed enum — `ProfileVocabDTO` only exists to
/// resolve a coffee's `profileId` to that enum by slug.
struct VocabDTO: Decodable {
    let countries: [Country]
    let roasters: [Roaster]
    let farms: [Farm]
    let profiles: [ProfileVocabDTO]
    /// Brew lab catalogues (PLAN.md §14) — sent in full every sync. Lenient
    /// and defaulted to `[]` when absent, same as `farms`: an older backend
    /// (or, symmetrically, a build predating this field) must not blank the
    /// rest of the snapshot over a block it doesn't know about yet.
    let brewOptions: [BrewOptionDTO]

    private enum CodingKeys: String, CodingKey {
        case countries, roasters, farms, profiles, brewOptions
    }

    // Lenient element decoding: one bad vocab row (e.g. the null-`iso2` Blend
    // row that used to throw) is skipped, not fatal to the whole snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        countries = try c.decode([FailableDecodable<Country>].self, forKey: .countries).compactMap(\.value)
        roasters = try c.decode([FailableDecodable<Roaster>].self, forKey: .roasters).compactMap(\.value)
        farms = try (c.decodeIfPresent([FailableDecodable<Farm>].self, forKey: .farms) ?? []).compactMap(\.value)
        profiles = try c.decode([FailableDecodable<ProfileVocabDTO>].self, forKey: .profiles).compactMap(\.value)
        brewOptions = try (c.decodeIfPresent([FailableDecodable<BrewOptionDTO>].self, forKey: .brewOptions) ?? [])
            .compactMap(\.value)
    }
}

struct ProfileVocabDTO: Decodable {
    let id: Int
    let slug: String
    let name: String
}

/// Mirrors `toCompactCoffee()` in the backend's `routes/coffees.js` — the
/// ~140 B/row shape (PLAN.md §4): ids only, no resolved names, no per-row
/// media URL, no notes/raw text (those are detail-only, `CoffeeDetailDTO`).
struct CompactCoffeeDTO: Decodable {
    let id: String
    let thumbUrl: String?
    /// #178(b): OPTIONAL, because `coffees.purchased_on` is nullable in the DB
    /// (008_coffees.sql:26) while this was the one required date in the DTO.
    /// A coffee with no purchase date therefore threw here and was silently
    /// dropped by `FailableDecodable` — a row that exists server-side and
    /// simply never appears in the app, with nothing logged. Every live row
    /// happens to have one today (checked: 0 of 414 null), so this is a latent
    /// bug, not an active one — but the wizard's `quick-create` path can
    /// produce a coffee whose photo has no `captured_at`, and that is exactly
    /// how it would start biting.
    let purchasedOn: PlainDate?
    let roasterId: Int?
    let roasterCountryId: Int?
    let originCountryIds: [Int]
    let originCountryId: Int?
    let isBlend: Bool
    let originFarmId: Int?
    let altitudeMinM: Int?
    let altitudeMaxM: Int?
    let profileId: Int?
    let profileDetail: String?
    let isDecaf: Bool
    let roastedOn: PlainDate?
    let priceOriginalAmount: Double?
    let priceOriginalCurrency: String?
    let priceEur: Double?
    let weightG: Int?
    let rating: Double?
    let isFavorite: Bool
    let reviewState: String
    let rotationQuarterTurns: Int?
    /// Brew lab (PLAN.md §14) — omitted by the backend (not `[]`) when a
    /// coffee has no trials, to stay near the ~140 B/row budget.
    let brewTried: [Int]?
    let brewBest: [Int]?

    private enum CodingKeys: String, CodingKey {
        case id, thumbUrl, roasterId, roasterCountryId, originCountryIds, originCountryId, isBlend, originFarmId
        case altitudeMinM, altitudeMaxM, profileId, profileDetail, isDecaf, roastedOn, purchasedOn
        case priceOriginalAmount, priceOriginalCurrency, priceEur, weightG, rating, isFavorite, reviewState
        case rotationQuarterTurns, brewTried, brewBest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        thumbUrl = try container.decodeIfPresent(String.self, forKey: .thumbUrl)
        purchasedOn = try container.decodeIfPresent(PlainDate.self, forKey: .purchasedOn)
        roasterId = try container.decodeIfPresent(Int.self, forKey: .roasterId)
        roasterCountryId = try container.decodeIfPresent(Int.self, forKey: .roasterCountryId)
        originCountryIds = try container.decodeIfPresent([Int].self, forKey: .originCountryIds) ?? []
        originCountryId = try container.decodeIfPresent(Int.self, forKey: .originCountryId)
        isBlend = try container.decode(Bool.self, forKey: .isBlend)
        originFarmId = try container.decodeIfPresent(Int.self, forKey: .originFarmId)
        altitudeMinM = try container.decodeIfPresent(Int.self, forKey: .altitudeMinM)
        altitudeMaxM = try container.decodeIfPresent(Int.self, forKey: .altitudeMaxM)
        profileId = try container.decodeIfPresent(Int.self, forKey: .profileId)
        profileDetail = try container.decodeIfPresent(String.self, forKey: .profileDetail)
        isDecaf = try container.decode(Bool.self, forKey: .isDecaf)
        roastedOn = try container.decodeIfPresent(PlainDate.self, forKey: .roastedOn)
        priceOriginalAmount = container.decodeFlexibleDouble(forKey: .priceOriginalAmount)
        priceOriginalCurrency = try container.decodeIfPresent(String.self, forKey: .priceOriginalCurrency)
        priceEur = container.decodeFlexibleDouble(forKey: .priceEur)
        weightG = try container.decodeIfPresent(Int.self, forKey: .weightG)
        rating = container.decodeFlexibleDouble(forKey: .rating)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        reviewState = try container.decode(String.self, forKey: .reviewState)
        rotationQuarterTurns = try container.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns)
        brewTried = try container.decodeIfPresent([Int].self, forKey: .brewTried)
        brewBest = try container.decodeIfPresent([Int].self, forKey: .brewBest)
    }
}


/// #178(b): a tiny counter for rows `FailableDecodable` skipped on the last
/// snapshot decode.
///
/// Deliberately a global rather than a return value: the decode happens inside
/// `Decodable.init(from:)`, which has nowhere to put an out-parameter, and
/// threading a context through every DTO to carry one diagnostic integer would
/// be worse than this. Written once per decode on whatever actor the decode
/// runs on and read on the main actor by `CoffeeStore.refresh()`, so it is a
/// simple locked box rather than an actor.
final class SnapshotDecodeStats: @unchecked Sendable {
    static let shared = SnapshotDecodeStats()

    private let lock = NSLock()
    private var dropped = 0

    private init() {}

    func record(dropped count: Int) {
        lock.lock()
        defer { lock.unlock() }
        dropped = count
    }

    /// A row that decoded fine but was skipped downstream — today only
    /// `CompactCoffeeDTO.makeCoffee` returning nil for a null `purchasedOn`.
    /// Added to the same total so Settings reports one number for "rows the
    /// snapshot had that the library does not".
    func recordExtraDrop() {
        lock.lock()
        defer { lock.unlock() }
        dropped += 1
    }

    var droppedRowCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return dropped
    }
}
