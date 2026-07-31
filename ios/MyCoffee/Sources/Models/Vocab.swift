import Foundation

/// Canonical vocabulary entities, as delivered by `/api/snapshot`'s `vocab`
/// block. `Coffee` rows reference these by integer id — dictionary-encoding is
/// what keeps the whole snapshot in the tens of KB (PLAN.md §4).

struct Country: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let isoCode: String          // ISO-3166 alpha-2, e.g. "ET"; drives the flag emoji in DesignSystem
    let name: String
    let isOrigin: Bool
    let isRoaster: Bool
    let isPseudo: Bool          // true only for the synthetic "Blend" row
}

struct Roaster: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let countryId: Int?
}

struct Farm: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
}

/// The full decoded vocabulary block, keyed for O(1) lookup by id.
struct Vocabulary: Codable, Sendable {
    let countries: [Int: Country]
    let roasters: [Int: Roaster]
    let farms: [Int: Farm]

    static let empty = Vocabulary(countries: [:], roasters: [:], farms: [:])

    init(countries: [Int: Country], roasters: [Int: Roaster], farms: [Int: Farm]) {
        self.countries = countries
        self.roasters = roasters
        self.farms = farms
    }

    init(countryList: [Country], roasterList: [Roaster], farmList: [Farm]) {
        countries = Dictionary(uniqueKeysWithValues: countryList.map { ($0.id, $0) })
        roasters = Dictionary(uniqueKeysWithValues: roasterList.map { ($0.id, $0) })
        farms = Dictionary(uniqueKeysWithValues: farmList.map { ($0.id, $0) })
    }

    // Snapshot payload transmits vocab as arrays; keyed dictionaries are a
    // client-side convenience, not the wire format.
    private enum CodingKeys: String, CodingKey {
        case countries, roasters, farms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let countryList = try container.decode([Country].self, forKey: .countries)
        let roasterList = try container.decode([Roaster].self, forKey: .roasters)
        let farmList = try container.decode([Farm].self, forKey: .farms)
        self.init(countryList: countryList, roasterList: roasterList, farmList: farmList)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(countries.values), forKey: .countries)
        try container.encode(Array(roasters.values), forKey: .roasters)
        try container.encode(Array(farms.values), forKey: .farms)
    }
}
