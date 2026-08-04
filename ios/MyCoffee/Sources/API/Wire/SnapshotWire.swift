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
    let purchasedOn: PlainDate
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

    private enum CodingKeys: String, CodingKey {
        case id, roasterId, roasterCountryId, originCountryIds, originCountryId, isBlend, originFarmId
        case altitudeMinM, altitudeMaxM, profileId, profileDetail, isDecaf, roastedOn, purchasedOn
        case priceOriginalAmount, priceOriginalCurrency, priceEur, weightG, rating, isFavorite, reviewState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        purchasedOn = try container.decode(PlainDate.self, forKey: .purchasedOn)
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
    }
}
