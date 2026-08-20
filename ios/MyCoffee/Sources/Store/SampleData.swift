import Foundation

/// Fixture data for `SampleCoffeeRepository` — the only data source until the
/// real backend snapshot lands (#22/#21). Deliberately varied: every
/// dimension, band, and "missing field" edge case the UX lane's screens need
/// to handle shows up somewhere here, including deliberately sparse facets
/// (e.g. a country with only a couple of coffees) so empty/thin states are
/// exercised, not just the happy path.
enum SampleData {
    static let vocabulary = Vocabulary(countryList: countries, roasterList: roasters, farmList: farms)

    static let coffees: [Coffee] = [
        make(id: "sample-001", purchased: (2026, 7, 15), roasterId: 1, roasterCountryId: 7,
             originCountryIds: [1], originCountryId: 1, originFarmId: 5,
             altitudeMinM: 1800, altitudeMaxM: 2000, profile: .washed,
             priceOriginalAmount: 18.5, priceOriginalCurrency: "EUR", priceEur: 18.5, fxRate: 1, fxRatePeriod: "2026-07",
             weightG: 200, rating: 4.6, isFavorite: true, favoriteSetBy: "human",
             farmLotNote: "Washed Nekisse, dried on raised beds for 14 days.",
             brewGuideNote: "V60, 92°C, 1:16, 3 pours.",
             roasterCopyNote: "Bright, floral, bergamot and jasmine.",
             rawTitle: "Ethiopia Nekisse", rawCaption: "Etiopia Nekisse, spalat"),

        make(id: "sample-002", purchased: (2026, 6, 2), roasterId: 2, roasterCountryId: 8,
             originCountryIds: [2], originCountryId: 2, originFarmId: 2,
             altitudeMinM: 1650, altitudeMaxM: 1650, profile: .natural,
             priceOriginalAmount: 420, priceOriginalCurrency: "CZK", priceEur: 16.4, fxRate: 0.039, fxRatePeriod: "2026-06",
             weightG: 250, rating: 4.3, rawTitle: "Colombia La Palma y El Tucán"),

        make(id: "sample-003", purchased: (2025, 11, 20), roasterId: 3, roasterCountryId: 9,
             originCountryIds: [6], originCountryId: 6,
             altitudeMinM: 1900, altitudeMaxM: 2100, profile: .anaerobic,
             priceOriginalAmount: 24, priceOriginalCurrency: "EUR", priceEur: 24, fxRate: 1, fxRatePeriod: "2025-11",
             weightG: 100, rating: 4.8, isFavorite: true, favoriteSetBy: "system",
             rawTitle: "Panama Anaerobic Natural"),

        make(id: "sample-004", purchased: (2025, 5, 10), roasterId: 4, roasterCountryId: 9,
             originCountryIds: [4], originCountryId: 4,
             altitudeMinM: 1700, altitudeMaxM: 1900, profile: .experimental, profileDetail: "Yellow Honey",
             priceOriginalAmount: 20, priceOriginalCurrency: "EUR", priceEur: 20, fxRate: 1, fxRatePeriod: "2025-05",
             weightG: 200, rawTitle: "Kenya Yellow Honey"),

        make(id: "sample-005", purchased: (2024, 12, 1), roasterId: 1, roasterCountryId: 7,
             originCountryIds: [3], originCountryId: 3,
             priceOriginalAmount: 12, priceOriginalCurrency: "EUR", priceEur: 12, fxRate: 1, fxRatePeriod: "2024-12",
             weightG: 250, rating: 3.2, rawTitle: "Brazilia", reviewState: "needs_review", minFieldConfidence: 0.4),

        make(id: "sample-006", purchased: (2024, 3, 18), roasterId: 5, roasterCountryId: 7,
             originCountryIds: [5], originCountryId: 5, originFarmId: 3,
             altitudeMinM: 1500, altitudeMaxM: 1500, profile: .coFermented,
             priceOriginalAmount: 22, priceOriginalCurrency: "EUR", priceEur: 22, fxRate: 1, fxRatePeriod: "2024-03",
             weightG: 100, rating: 4.1, rawTitle: "Guatemala Co-ferment"),

        make(id: "sample-007", purchased: (2023, 9, 9), roasterId: 6, roasterCountryId: 8,
             originCountryIds: [1], originCountryId: 1, originFarmId: 5,
             altitudeMinM: 2000, altitudeMaxM: 2200, profile: .washed,
             weightG: 200, rating: 4.0, rawTitle: "Ethiopia Washed"),

        make(id: "sample-008", purchased: (2022, 7, 4), roasterId: 2, roasterCountryId: 8,
             originCountryIds: [2, 3], originCountryId: 2, isBlend: true,
             altitudeMinM: 1200, altitudeMaxM: 1600, profile: .natural,
             priceOriginalAmount: 14, priceOriginalCurrency: "EUR", priceEur: 14, fxRate: 1, fxRatePeriod: "2022-07",
             weightG: 200, rating: 3.9, rawTitle: "House Blend"),

        make(id: "sample-009", purchased: (2021, 2, 14), roasterId: 7, roasterCountryId: 10,
             originCountryIds: [4], originCountryId: 4,
             altitudeMinM: 900, altitudeMaxM: 1100, profile: .washed,
             priceOriginalAmount: 15, priceOriginalCurrency: "EUR", priceEur: 15, fxRate: 1, fxRatePeriod: "2021-02",
             weightG: 200, rating: 2.8, rawTitle: "Kenya AA"),

        make(id: "sample-010", purchased: (2020, 8, 30), roasterId: 8, roasterCountryId: 10,
             originCountryIds: [6], originCountryId: 6,
             altitudeMinM: 1000, altitudeMaxM: 1000, profile: .anaerobic,
             priceOriginalAmount: 26, priceOriginalCurrency: "EUR", priceEur: 26, fxRate: 1, fxRatePeriod: "2020-08",
             weightG: 100, rating: 4.9, isFavorite: true, favoriteSetBy: "human", rawTitle: "Panama Geisha"),

        make(id: "sample-011", purchased: (2019, 6, 15), roasterId: 9, roasterCountryId: 9,
             originCountryIds: [2], originCountryId: 2, originFarmId: 2,
             altitudeMinM: 1650, altitudeMaxM: 1750,
             isDecaf: true,
             priceOriginalAmount: 13, priceOriginalCurrency: "EUR", priceEur: 13, fxRate: 1, fxRatePeriod: "2019-06",
             weightG: 250, rating: 3.6, rawTitle: "Colombia Decaf, Swiss Water"),

        make(id: "sample-012", purchased: (2015, 1, 10), roasterId: 10, roasterCountryId: nil,
             originCountryIds: [1], originCountryId: 1,
             altitudeMinM: 1800, altitudeMaxM: 1800, profile: .washed,
             priceOriginalAmount: 45, priceOriginalCurrency: "RON", priceEur: 10.03, fxRate: 0.222856, fxRatePeriod: "2015-01",
             weightG: 200, rating: 4.0, rawTitle: "Ethiopia (roaster unknown)"),

        make(id: "sample-013", purchased: (2026, 5, 3), roasterId: 1, roasterCountryId: 7,
             originCountryIds: [1], originCountryId: 1, originFarmId: 5,
             altitudeMinM: 1750, altitudeMaxM: 1950, profile: .washed,
             priceOriginalAmount: 19, priceOriginalCurrency: "EUR", priceEur: 19, fxRate: 1, fxRatePeriod: "2026-05",
             weightG: 200, rating: 4.7, isFavorite: true, favoriteSetBy: "human", rawTitle: "Ethiopia Nekisse Lot 2"),

        make(id: "sample-014", purchased: (2026, 4, 20), roasterId: 3, roasterCountryId: 9,
             originCountryIds: [1], originCountryId: 1,
             altitudeMinM: 1600, altitudeMaxM: 1900, profile: .anaerobic,
             priceOriginalAmount: 21, priceOriginalCurrency: "EUR", priceEur: 21, fxRate: 1, fxRatePeriod: "2026-04",
             weightG: 100, rating: 4.5, isFavorite: true, favoriteSetBy: "human", rawTitle: "Ethiopia Anaerobic Natural"),

        make(id: "sample-015", purchased: (2026, 3, 8), roasterId: 4, roasterCountryId: 9,
             originCountryIds: [4], originCountryId: 4, originFarmId: 4,
             altitudeMinM: 1750, altitudeMaxM: 1950, profile: .anaerobic,
             priceOriginalAmount: 23, priceOriginalCurrency: "EUR", priceEur: 23, fxRate: 1, fxRatePeriod: "2026-03",
             weightG: 100, rating: 4.55, rawTitle: "Kenya Kayanza Anaerobic"),

        make(id: "sample-016", purchased: (2026, 2, 1), roasterId: 5, roasterCountryId: 7,
             originCountryIds: [4], originCountryId: 4,
             altitudeMinM: 1800, altitudeMaxM: 2000, profile: .anaerobic,
             priceOriginalAmount: 25, priceOriginalCurrency: "EUR", priceEur: 25, fxRate: 1, fxRatePeriod: "2026-02",
             weightG: 100, rating: 4.65, isFavorite: true, favoriteSetBy: "human", rawTitle: "Kenya Anaerobic"),

        make(id: "sample-017", purchased: (2026, 1, 12), roasterId: 6, roasterCountryId: 8,
             originCountryIds: [2], originCountryId: 2, originFarmId: 2,
             altitudeMinM: 1700, altitudeMaxM: 1700, profile: .anaerobic,
             priceOriginalAmount: 22, priceOriginalCurrency: "EUR", priceEur: 22, fxRate: 1, fxRatePeriod: "2026-01",
             weightG: 100, rating: 4.75, rawTitle: "Colombia Anaerobic"),

        make(id: "sample-018", purchased: (2025, 8, 22), roasterId: 2, roasterCountryId: 8,
             originCountryIds: [2], originCountryId: 2,
             altitudeMinM: 1600, altitudeMaxM: 1800, profile: .natural,
             priceOriginalAmount: 17, priceOriginalCurrency: "EUR", priceEur: 17, fxRate: 1, fxRatePeriod: "2025-08",
             weightG: 250, rating: 4.2, rawTitle: "Colombia Natural"),

        make(id: "sample-019", purchased: (2025, 3, 30), roasterId: 1, roasterCountryId: 7,
             originCountryIds: [4], originCountryId: 4, originFarmId: 4,
             altitudeMinM: 1650, altitudeMaxM: 1850, profile: .washed,
             priceOriginalAmount: 18, priceOriginalCurrency: "EUR", priceEur: 18, fxRate: 1, fxRatePeriod: "2025-03",
             weightG: 200, rating: 4.4, rawTitle: "Kenya Washed"),

        make(id: "sample-020", purchased: (2024, 10, 5), roasterId: 3, roasterCountryId: 9,
             originCountryIds: [5], originCountryId: 5,
             altitudeMinM: 1400, altitudeMaxM: 1600, profile: .natural,
             priceOriginalAmount: 19, priceOriginalCurrency: "EUR", priceEur: 19, fxRate: 1, fxRatePeriod: "2024-10",
             weightG: 200, rawTitle: "Guatemala Natural"),

        make(id: "sample-021", purchased: (2024, 1, 9), roasterId: 8, roasterCountryId: 10,
             originCountryIds: [3], originCountryId: 3,
             priceOriginalAmount: 11, priceOriginalCurrency: "EUR", priceEur: 11, fxRate: 1, fxRatePeriod: "2024-01",
             weightG: 250, rating: 3.4, rawTitle: "Brazil Pulped Natural"),

        make(id: "sample-022", purchased: (2023, 4, 17), roasterId: 9, roasterCountryId: 9,
             originCountryIds: [3], originCountryId: 3,
             altitudeMinM: 1100, altitudeMaxM: 1300,
             priceOriginalAmount: 10.5, priceOriginalCurrency: "EUR", priceEur: 10.5, fxRate: 1, fxRatePeriod: "2023-04",
             weightG: 250, rating: 3.7, rawTitle: "Brazil"),
    ]

    // MARK: - Vocabulary

    private static let countries: [Country] = [
        Country(id: 1, isoCode: "ET", name: "Ethiopia", isOrigin: true, isRoaster: false, isPseudo: false),
        Country(id: 2, isoCode: "CO", name: "Colombia", isOrigin: true, isRoaster: false, isPseudo: false),
        Country(id: 3, isoCode: "BR", name: "Brazil", isOrigin: true, isRoaster: false, isPseudo: false),
        Country(id: 4, isoCode: "KE", name: "Kenya", isOrigin: true, isRoaster: false, isPseudo: false),
        Country(id: 5, isoCode: "GT", name: "Guatemala", isOrigin: true, isRoaster: false, isPseudo: false),
        Country(id: 6, isoCode: "PA", name: "Panama", isOrigin: true, isRoaster: false, isPseudo: false),
        Country(id: 7, isoCode: "NL", name: "Netherlands", isOrigin: false, isRoaster: true, isPseudo: false),
        Country(id: 8, isoCode: "CZ", name: "Czech Republic", isOrigin: false, isRoaster: true, isPseudo: false),
        Country(id: 9, isoCode: "RO", name: "Romania", isOrigin: false, isRoaster: true, isPseudo: false),
        Country(id: 10, isoCode: "DK", name: "Denmark", isOrigin: false, isRoaster: true, isPseudo: false),
        Country(id: 11, isoCode: "XX", name: "Blend", isOrigin: true, isRoaster: false, isPseudo: true),
    ]

    private static let roasters: [Roaster] = [
        Roaster(id: 1, name: "DAK Coffee Roasters", countryId: 7),
        Roaster(id: 2, name: "Father's Coffee Roastery", countryId: 8),
        Roaster(id: 3, name: "Right Side", countryId: 9),
        Roaster(id: 4, name: "BOO Modern Coffee", countryId: 9),
        Roaster(id: 5, name: "Beansmith's", countryId: 7),
        Roaster(id: 6, name: "CandyCane Coffee", countryId: 8),
        Roaster(id: 7, name: "Nordic Roasters", countryId: 10),
        Roaster(id: 8, name: "La Cabra", countryId: 10),
        Roaster(id: 9, name: "Terroir Coffee", countryId: 9),
        Roaster(id: 10, name: "Unlabeled Roastery", countryId: nil),
    ]

    private static let farms: [Farm] = [
        Farm(id: 1, name: "Finca El Paraiso"),
        Farm(id: 2, name: "La Palma y El Tucán"),
        Farm(id: 3, name: "El Injerto"),
        Farm(id: 4, name: "Kayanza Washing Station"),
        Farm(id: 5, name: "Nekisse"),
    ]

    // MARK: - Factory

    private static func make(
        id: String,
        purchased: (Int, Int, Int),
        roasterId: Int,
        roasterCountryId: Int?,
        originCountryIds: [Int],
        originCountryId: Int?,
        isBlend: Bool = false,
        originFarmId: Int? = nil,
        altitudeMinM: Int? = nil,
        altitudeMaxM: Int? = nil,
        profile: Profile? = nil,
        profileDetail: String? = nil,
        isDecaf: Bool = false,
        roasted: (Int, Int, Int)? = nil,
        priceOriginalAmount: Double? = nil,
        priceOriginalCurrency: String? = nil,
        priceEur: Double? = nil,
        fxRate: Double? = nil,
        fxRatePeriod: String? = nil,
        weightG: Int? = nil,
        rating: Double? = nil,
        isFavorite: Bool = false,
        favoriteSetBy: String? = nil,
        farmLotNote: String? = nil,
        brewGuideNote: String? = nil,
        roasterCopyNote: String? = nil,
        rawTitle: String? = nil,
        rawCaption: String? = nil,
        rawDescription: String? = nil,
        reviewState: String = "clean",
        minFieldConfidence: Double? = nil
    ) -> Coffee {
        Coffee(
            id: id,
            purchasedOn: PlainDate(year: purchased.0, month: purchased.1, day: purchased.2),
            roasterId: roasterId,
            roasterCountryId: roasterCountryId,
            originCountryIds: originCountryIds,
            originCountryId: originCountryId,
            isBlend: isBlend,
            originFarmId: originFarmId,
            altitudeMinM: altitudeMinM,
            altitudeMaxM: altitudeMaxM,
            profile: profile,
            profileDetail: profileDetail,
            isDecaf: isDecaf,
            roastedOn: roasted.map { PlainDate(year: $0.0, month: $0.1, day: $0.2) },
            priceOriginalAmount: priceOriginalAmount,
            priceOriginalCurrency: priceOriginalCurrency,
            priceEur: priceEur,
            fxRate: fxRate,
            fxRatePeriod: fxRatePeriod,
            weightG: weightG,
            rating: rating,
            isFavorite: isFavorite,
            favoriteSetBy: favoriteSetBy,
            farmLotNote: farmLotNote,
            brewGuideNote: brewGuideNote,
            roasterCopyNote: roasterCopyNote,
            rawTitle: rawTitle,
            rawCaption: rawCaption,
            rawDescription: rawDescription,
            reviewState: reviewState,
            minFieldConfidence: minFieldConfidence,
            rotationQuarterTurns: nil,
            images: nil
        )
    }
}
