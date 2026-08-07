import Foundation

/// Translates `profiles` vocab rows (id/slug/name from the DB) to the
/// client's fixed `Profile` enum, matched by slug. An id whose slug the
/// client's build doesn't recognize maps to `nil` — same as a coffee with no
/// profile at all — rather than crashing on a vocabulary the running app
/// predates.
func profileMap(from entries: [ProfileVocabDTO]) -> [Int: Profile] {
    var result: [Int: Profile] = [:]
    for entry in entries {
        if let profile = Profile(rawValue: entry.slug) {
            result[entry.id] = profile
        }
    }
    return result
}

extension CompactCoffeeDTO {
    /// Builds the app's canonical `Coffee` from a compact snapshot row.
    /// Fields the compact shape doesn't carry (notes, raw text, images,
    /// `fxRate`) come back `nil` until `CoffeeDetailDTO.makeCoffee` enriches
    /// this same id via an on-demand detail fetch (PLAN.md §4).
    func makeCoffee(profilesByID: [Int: Profile]) -> Coffee {
        Coffee(
            id: id,
            purchasedOn: purchasedOn,
            roasterId: roasterId,
            roasterCountryId: roasterCountryId,
            originCountryIds: originCountryIds,
            originCountryId: originCountryId,
            isBlend: isBlend,
            originFarmId: originFarmId,
            altitudeMinM: altitudeMinM,
            altitudeMaxM: altitudeMaxM,
            profile: profileId.flatMap { profilesByID[$0] },
            profileDetail: profileDetail,
            isDecaf: isDecaf,
            roastedOn: roastedOn,
            priceOriginalAmount: priceOriginalAmount,
            priceOriginalCurrency: priceOriginalCurrency,
            priceEur: priceEur,
            fxRate: nil,
            fxRatePeriod: nil,
            weightG: weightG,
            rating: rating,
            isFavorite: isFavorite,
            favoriteSetBy: nil,
            farmLotNote: nil,
            brewGuideNote: nil,
            roasterCopyNote: nil,
            rawTitle: nil,
            rawCaption: nil,
            rawDescription: nil,
            reviewState: reviewState,
            minFieldConfidence: nil,
            // The compact snapshot now carries a signed thumbnail so the listing
            // shows photos (and a re-sync doesn't wipe a detail-loaded thumb).
            // `display` is seeded from the same URL as a reasonable hero
            // placeholder until a detail fetch supplies the full-size one.
            images: thumbUrl.map { CoffeeImageURLs(thumb: $0, display: $0, ocr: nil) }
        )
    }
}

extension CoffeeDetailDTO {
    /// Builds a fully-populated `Coffee` from a detail fetch — a superset of
    /// `CompactCoffeeDTO.makeCoffee`, since the detail route spreads every
    /// compact field plus notes/raw text/images.
    func makeCoffee(profilesByID: [Int: Profile]) -> Coffee {
        Coffee(
            id: id,
            purchasedOn: purchasedOn,
            roasterId: roasterId,
            roasterCountryId: roasterCountryId,
            originCountryIds: originCountryIds,
            originCountryId: originCountryId,
            isBlend: isBlend,
            originFarmId: originFarmId,
            altitudeMinM: altitudeMinM,
            altitudeMaxM: altitudeMaxM,
            profile: profileId.flatMap { profilesByID[$0] },
            profileDetail: profileDetail,
            isDecaf: isDecaf,
            roastedOn: roastedOn,
            priceOriginalAmount: priceOriginalAmount,
            priceOriginalCurrency: priceOriginalCurrency,
            priceEur: priceEur,
            fxRate: nil,
            fxRatePeriod: nil,
            weightG: weightG,
            rating: rating,
            isFavorite: isFavorite,
            favoriteSetBy: nil,
            farmLotNote: descFarmLot,
            brewGuideNote: descBrewGuide,
            roasterCopyNote: descRoasterCopy,
            rawTitle: rawTitle,
            rawCaption: rawCaption,
            rawDescription: rawDescription,
            reviewState: reviewState,
            minFieldConfidence: minFieldConfidence,
            images: (thumbUrl != nil || displayUrl != nil)
                ? CoffeeImageURLs(thumb: thumbUrl ?? "", display: displayUrl ?? "", ocr: nil)
                : nil
        )
    }
}
