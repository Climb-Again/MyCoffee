import Foundation

/// View-layer presentation helpers over the shell-owned `Coffee`/`SortOption`/
/// `FacetKey` types. Kept here (Features, UX-owned) rather than added to
/// `Models`/`Query` (shell-owned) — extensions don't require editing the
/// original declaration.
extension Coffee {
    /// The row/detail title. Missing fields never render "N/A" (PLAN.md
    /// §6.3), so this falls back through farm, then origin country, before
    /// giving up.
    func displayTitle(vocabulary: Vocabulary) -> String {
        if let rawTitle, !rawTitle.trimmingCharacters(in: .whitespaces).isEmpty { return rawTitle }
        if let farmID = originFarmId, let farm = vocabulary.farms[farmID] { return farm.name }
        if let countryID = originCountryId, let country = vocabulary.countries[countryID] { return country.name }
        return "Unlabeled coffee"
    }

    func roaster(vocabulary: Vocabulary) -> Roaster? { vocabulary.roasters[roasterId] }
    func roasterCountry(vocabulary: Vocabulary) -> Country? { roasterCountryId.flatMap { vocabulary.countries[$0] } }
    func primaryOriginCountry(vocabulary: Vocabulary) -> Country? { originCountryId.flatMap { vocabulary.countries[$0] } }
    func originFarm(vocabulary: Vocabulary) -> Farm? { originFarmId.flatMap { vocabulary.farms[$0] } }

    /// "Farm, Country" — either half may be missing; the whole line omits
    /// itself (returns `nil`) only when both are.
    func originSubtitle(vocabulary: Vocabulary) -> String? {
        let farmName = originFarm(vocabulary: vocabulary)?.name
        let countryName: String? = {
            if isBlend { return "Blend" }
            return primaryOriginCountry(vocabulary: vocabulary)?.name
        }()
        switch (farmName, countryName) {
        case let (.some(f), .some(c)): return "\(f), \(c)"
        case let (.some(f), nil): return f
        case let (nil, .some(c)): return c
        case (nil, nil): return nil
        }
    }

    /// Altitude range, e.g. "1800 – 2000 m" / "1800 m" for a single value.
    var altitudeLabel: String? {
        switch (altitudeMinM, altitudeMaxM) {
        case let (.some(lo), .some(hi)) where lo == hi: return "\(lo) m"
        case let (.some(lo), .some(hi)): return "\(lo) – \(hi) m"
        case let (.some(lo), nil): return "\(lo) m"
        case let (nil, .some(hi)): return "\(hi) m"
        case (nil, nil): return nil
        }
    }

    var weightLabel: String? {
        guard let weightG else { return nil }
        return "\(weightG) g"
    }

    var priceLabel: String? {
        guard let priceEur else { return nil }
        return priceEur.formatted(.currency(code: "EUR"))
    }

    var pricePer100gLabel: String? {
        guard let pricePer100gEur else { return nil }
        return pricePer100gEur.formatted(.currency(code: "EUR")) + " / 100 g"
    }
}

/// `Profile` (`Models/Profile.swift`, shell-owned) declares `String, Codable,
/// CaseIterable, Sendable, Identifiable` but not `Hashable` — and Swift only
/// synthesizes `Equatable`/`Hashable` when a type declares conformance in its
/// *original* file, so without this the module doesn't build at all:
/// `CoffeeFilter.profiles: Set<Profile>` and `FacetKey.profile(Profile)`
/// (both shell-owned too) both require it. Added here rather than in
/// `Profile.swift` to respect the "never touch shell files" rule; flagged in
/// `status/ios-ux.md` in case shell prefers to move it into the original
/// declaration instead, which would make this extension redundant.
extension Profile: Hashable {
    static func == (lhs: Profile, rhs: Profile) -> Bool { lhs.rawValue == rhs.rawValue }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

extension SortOption: Hashable {
    /// Manual conformance — `SortOption` lives in `Query/` (shell-owned) and
    /// wasn't declared `Hashable` there. Auto-synthesis only works from the
    /// original declaration's file, so this implements the requirements by
    /// hand instead of asking the compiler to derive them.
    static func == (lhs: SortOption, rhs: SortOption) -> Bool { lhs.sortKey == rhs.sortKey }
    func hash(into hasher: inout Hasher) { hasher.combine(sortKey) }

    private var sortKey: Int {
        switch self {
        case .dateBought: return 0
        case .rating: return 1
        case .price: return 2
        case .pricePer100g: return 3
        }
    }

    var displayName: String {
        switch self {
        case .dateBought: return "Date bought"
        case .rating: return "Rating"
        case .price: return "Price"
        case .pricePer100g: return "Price / 100 g"
        }
    }
}

extension FilterDimension {
    var title: String {
        switch self {
        case .roaster: return "Roaster"
        case .roasterCountry: return "Roaster country"
        case .originCountry: return "Origin country"
        case .farm: return "Farm"
        case .profile: return "Process"
        case .decaf: return "Decaf"
        case .favorite: return "Favourites"
        case .ratingBand: return "Rating"
        case .priceBand: return "Price"
        case .pricePer100gBand: return "Price / 100 g"
        case .altitudeBand: return "Altitude"
        case .year: return "Year"
        }
    }

    /// Roaster and Farm run into the hundreds of values — the "Show all"
    /// searchable list is mandatory for these two (PLAN.md §6.2), optional
    /// (triggered only past 8 entries) for everything else.
    var alwaysNeedsFullList: Bool {
        switch self {
        case .roaster, .farm: return true
        default: return false
        }
    }
}

/// A facet value's display label, given the dimension it belongs to (needed
/// to resolve `.vocabID` against the right vocabulary table) and its
/// aggregate stats.
func facetLabel(_ key: FacetKey, dimension: FilterDimension, vocabulary: Vocabulary) -> String {
    switch key {
    case let .vocabID(id):
        switch dimension {
        case .roaster: return vocabulary.roasters[id]?.name ?? "Unknown"
        case .roasterCountry, .originCountry: return vocabulary.countries[id]?.name ?? "Unknown"
        case .farm: return vocabulary.farms[id]?.name ?? "Unknown"
        default: return "Unknown"
        }
    case let .profile(profile): return profile.displayName
    case let .bool(value):
        switch dimension {
        case .decaf: return value ? "Decaf" : "Not decaf"
        case .favorite: return "Favourites only"
        default: return value ? "Yes" : "No"
        }
    case let .ratingBand(band): return band.label
    case let .priceBand(band):
        return dimension == .pricePer100gBand ? band.label + " / 100 g" : band.label
    case let .altitudeBand(band): return band.label
    case let .year(year): return "\(year)"
    case .unknown: return "Unknown"
    }
}
