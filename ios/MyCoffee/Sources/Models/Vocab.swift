import Foundation

/// Canonical vocabulary entities, as delivered by `/api/snapshot`'s `vocab`
/// block. `Coffee` rows reference these by integer id — dictionary-encoding is
/// what keeps the whole snapshot in the tens of KB (PLAN.md §4).

struct Country: Identifiable, Hashable, Sendable {
    let id: Int
    let isoCode: String?         // ISO-3166 alpha-2, e.g. "ET"; nil for the synthetic "Blend" row (iso2 is NULL). Drives the flag emoji.
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
        // nil for the "Blend" pseudo-country (iso2 is NULL). Decoding this as a
        // required String threw on Blend — which is in EVERY snapshot — failing
        // the whole vocab array and blanking the entire app.
        isoCode = try container.decodeIfPresent(String.self, forKey: .isoCode)
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
    /// #134: roaster-page content, carried from the snapshot vocab block once
    /// #132 populates them. Optional — most roasters have neither yet, and a
    /// nil logo falls back to `MonogramAvatar`, a nil/empty blurb omits the
    /// section. Logos are **web-only, not cached** (Radu, 2026-09-07), so the
    /// page fetches `logoUrl` directly rather than through `ImageStore`.
    var blurb: String? = nil
    var logoUrl: String? = nil

    /// The snapshot's roaster vocab block is the raw DB row shape, so its
    /// country key is snake-case `country_id` (unlike `coffees`, which are
    /// camelCased by `toCompactCoffee`). Without this mapping `countryId`
    /// silently decoded to nil for *every* roaster, so the country never
    /// showed on a roaster page. `blurb`/`logoUrl` already match by name
    /// (aliased `logo_url AS "logoUrl"` server-side).
    private enum CodingKeys: String, CodingKey {
        case id, name, blurb, logoUrl
        case countryId = "country_id"
    }
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
    /// Brew lab catalogues (PLAN.md §14, #155/#156) — recipes/devices/grinds/
    /// temps, all four kinds in one dictionary keyed by `BrewOption.id`.
    let brewOptions: [Int: BrewOption]

    static let empty = Vocabulary(countries: [:], roasters: [:], farms: [:], brewOptions: [:])

    init(
        countries: [Int: Country], roasters: [Int: Roaster], farms: [Int: Farm],
        brewOptions: [Int: BrewOption] = [:]
    ) {
        self.countries = countries
        self.roasters = roasters
        self.farms = farms
        self.brewOptions = brewOptions
    }

    init(
        countryList: [Country], roasterList: [Roaster], farmList: [Farm],
        brewOptionList: [BrewOption] = []
    ) {
        countries = Dictionary(uniqueKeysWithValues: countryList.map { ($0.id, $0) })
        roasters = Dictionary(uniqueKeysWithValues: roasterList.map { ($0.id, $0) })
        farms = Dictionary(uniqueKeysWithValues: farmList.map { ($0.id, $0) })
        brewOptions = Dictionary(uniqueKeysWithValues: brewOptionList.map { ($0.id, $0) })
    }

    // Snapshot payload transmits vocab as arrays; keyed dictionaries are a
    // client-side convenience, not the wire format.
    private enum CodingKeys: String, CodingKey {
        case countries, roasters, farms, brewOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let countryList = try container.decode([Country].self, forKey: .countries)
        let roasterList = try container.decode([Roaster].self, forKey: .roasters)
        let farmList = try container.decode([Farm].self, forKey: .farms)
        // No schema bump (PLAN.md §14): an on-disk snapshot written before the
        // brew lab shipped simply has no `brewOptions` key at all.
        let brewOptionList = try container.decodeIfPresent([BrewOption].self, forKey: .brewOptions) ?? []
        self.init(countryList: countryList, roasterList: roasterList, farmList: farmList, brewOptionList: brewOptionList)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(countries.values), forKey: .countries)
        try container.encode(Array(roasters.values), forKey: .roasters)
        try container.encode(Array(farms.values), forKey: .farms)
        try container.encode(Array(brewOptions.values), forKey: .brewOptions)
    }

    /// Every live option of one kind, sorted `sortOrder` → `valueNum` →
    /// `label`. Archived rows are excluded unless `includeArchived` is set, in
    /// which case they sort after every live one — used by `BrewLabSheet`
    /// (#157) to still render an archived option a coffee already tried.
    func brewOptions(of kind: BrewKind, includeArchived: Bool = false) -> [BrewOption] {
        brewOptions.values
            .filter { $0.kind == kind && (includeArchived || !$0.archived) }
            .sorted { lhs, rhs in
                if lhs.archived != rhs.archived { return !lhs.archived }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                switch (lhs.valueNum, rhs.valueNum) {
                case let (.some(l), .some(r)) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
                return lhs.label < rhs.label
            }
    }

    /// Looks up a `.grind`/`.temp` option by its numeric value — the client-side
    /// mirror of the server's recipe auto-tick (`getOrCreateNumericOption` in
    /// `routes/brew.js`), used to optimistically tick a recipe's nominal grind
    /// and temperature locally before the flush response confirms it.
    func brewOption(kind: BrewKind, value: Double) -> BrewOption? {
        brewOptions.values.first { $0.kind == kind && $0.valueNum == value }
    }

    /// A copy with one option inserted/replaced — used right after
    /// `createBrewOption`/`updateBrewOption` round-trips, so the new/renamed
    /// row is visible immediately rather than waiting for the next sync.
    func insertingBrewOption(_ option: BrewOption) -> Vocabulary {
        var updated = brewOptions
        updated[option.id] = option
        return Vocabulary(countries: countries, roasters: roasters, farms: farms, brewOptions: updated)
    }
}
