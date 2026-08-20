import Foundation

/// Mirrors `GET /api/coffees/:publicId` in the backend's `routes/coffees.js`:
/// every `CompactCoffeeDTO` field (it spreads `toCompactCoffee(row)`) plus the
/// notes, raw extracted text, `minFieldConfidence`, and signed thumb/display
/// URLs that the compact snapshot omits to stay near its ~140 B/row budget
/// (PLAN.md §4). `rails` isn't decoded — it's always `[]` until #23/#24 land
/// extraction data, and nothing client-side reads it yet.
struct CoffeeDetailDTO: Decodable {
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
    let rotationQuarterTurns: Int?

    let descFarmLot: String?
    let descBrewGuide: String?
    let descRoasterCopy: String?
    let rawTitle: String?
    let rawCaption: String?
    let rawDescription: String?
    let minFieldConfidence: Double?
    let thumbUrl: String?
    let displayUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id, roasterId, roasterCountryId, originCountryIds, originCountryId, isBlend, originFarmId
        case altitudeMinM, altitudeMaxM, profileId, profileDetail, isDecaf, roastedOn, purchasedOn
        case priceOriginalAmount, priceOriginalCurrency, priceEur, weightG, rating, isFavorite, reviewState
        case rotationQuarterTurns
        case descFarmLot, descBrewGuide, descRoasterCopy, rawTitle, rawCaption, rawDescription
        case minFieldConfidence, thumbUrl, displayUrl
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
        rotationQuarterTurns = try container.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns)

        descFarmLot = try container.decodeIfPresent(String.self, forKey: .descFarmLot)
        descBrewGuide = try container.decodeIfPresent(String.self, forKey: .descBrewGuide)
        descRoasterCopy = try container.decodeIfPresent(String.self, forKey: .descRoasterCopy)
        rawTitle = try container.decodeIfPresent(String.self, forKey: .rawTitle)
        rawCaption = try container.decodeIfPresent(String.self, forKey: .rawCaption)
        rawDescription = try container.decodeIfPresent(String.self, forKey: .rawDescription)
        minFieldConfidence = container.decodeFlexibleDouble(forKey: .minFieldConfidence)
        thumbUrl = try container.decodeIfPresent(String.self, forKey: .thumbUrl)
        displayUrl = try container.decodeIfPresent(String.self, forKey: .displayUrl)
    }
}
