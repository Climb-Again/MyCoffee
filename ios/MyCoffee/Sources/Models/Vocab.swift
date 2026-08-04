import Foundation

/// Canonical vocabulary entities, as delivered by `/api/snapshot`'s `vocab`
/// block. `Coffee` rows reference these by integer id — dictionary-encoding is
/// what keeps the whole snapshot in the tens of KB (PLAN.md §4).

struct Country: Identifiable, Hashable, Sendable {
    let id: Int
    let isoCode: String          // ISO-3166 alpha-2, e.g. "ET"; drives the flag emoji in DesignSystem
    let name: String
    let isOrigin: Bool
    let isRoaster: Bool
    let isPseudo: Bool          // true only for the synthetic "Blend" row
}

extension Country: Codable {
    // The wire shape (`loadCountryVocab` in the backend's `vocab.js`) is a raw
    // `SELECT id, name, iso2, is_origin, is_roaster, kind FROM countries` row,
    // not this struct's field names: the ISO column is `iso2`, and there is no
    // `is_pseudo` boolean at all — "pseudo" is one value of the string `kind`
    // column (the others being "origin"/"roaster"). Custom coding translates
    // between the two so every other call site can keep using `isoCode`/
    // `isPseudo` as if the wire matched — `Roaster`/`Farm` don't need this,
    // their columns already line up under `.convertFromSnakeCase`.
    private enum CodingKeys: String, CodingKey {
        case id, name, isOrigin, isRoaster, kind
        case isoCode = "iso2"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        isoCode = try container.decode(String.self, forKey: .isoCode)
        name = try container.decode(String.self, forKey: .name)
        isOrigin = try container.decode(Bool.self, forKey: .isOrigin)
        isRoaster = try container.decode(Bool.self, forKey: .isRoaster)
        isPseudo = try container.decodeIfPresent(String.self, forKey: .kind) == "pseudo"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isoCode, forKey: .isoCode)
        try container.encode(name, forKey: .name)
        try container.encode(isOrigin, forKey: .isOrigin)
        try container.encode(isRoaster, forKey: .isRoaster)
        try container.encode(isPseudo ? "pseudo" : "regular", forKey: .kind)
    }
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
