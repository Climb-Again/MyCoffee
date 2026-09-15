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

extension BrewOption {
    /// `nil` when `dto.kind` isn't one of the four the client's build
    /// recognizes — same "unknown vocab maps to absent, never crashes"
    /// stance as `profileMap`.
    init?(dto: BrewOptionDTO) {
        guard let kind = BrewKind(rawValue: dto.kind) else { return nil }
        self.init(
            id: dto.id,
            kind: kind,
            label: dto.label,
            detail: dto.detail,
            valueNum: dto.valueNum,
            recipe: dto.recipe.map {
                BrewRecipeSpec(
                    doseG: $0.doseG, pours: $0.pours, mlPerPour: $0.mlPerPour,
                    totalWaterMl: $0.totalWaterMl, grindClicks: $0.grindClicks, waterTempC: $0.waterTempC
                )
            },
            sortOrder: dto.sortOrder,
            archived: dto.archived
        )
    }
}

extension CompactCoffeeDTO {
    /// Builds the app's canonical `Coffee` from a compact snapshot row.
    /// Fields the compact shape doesn't carry (notes, raw text, images,
    /// `fxRate`) come back `nil` until `CoffeeDetailDTO.makeCoffee` enriches
    /// this same id via an on-demand detail fetch (PLAN.md §4).
    /// #211: no longer failable. `Coffee.purchasedOn` is now optional (widened
    /// to match this DTO's own nullable field, #178(b)'s deferred half), so a
    /// coffee with no purchase date decodes and appears like any other instead
    /// of being dropped and counted via `SnapshotDecodeStats.recordExtraDrop()`.
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
            flavorNotes: nil,
            rawTitle: nil,
            rawCaption: nil,
            rawDescription: nil,
            reviewState: reviewState,
            minFieldConfidence: nil,
            rotationQuarterTurns: rotationQuarterTurns,
            // The compact snapshot now carries a signed thumbnail so the listing
            // shows photos (and a re-sync doesn't wipe a detail-loaded thumb).
            // `display` is left as the empty-string "no URL yet" sentinel
            // (matching `CoffeeDetailDTO.makeCoffee`'s `?? ""` below) rather
            // than seeded from the thumb URL — seeding it produced a 320-px
            // thumb blown up to the hero's 300pt frame that then swapped to
            // the real photo once a detail fetch landed (#180, iOS UX).
            images: thumbUrl.map { CoffeeImageURLs(thumb: $0, display: "", ocr: nil) },
            brewTriedIds: brewTried,
            brewBestIds: brewBest
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
            flavorNotes: flavorNotes,
            rawTitle: rawTitle,
            rawCaption: rawCaption,
            rawDescription: rawDescription,
            reviewState: reviewState,
            minFieldConfidence: minFieldConfidence,
            rotationQuarterTurns: rotationQuarterTurns,
            images: (thumbUrl != nil || displayUrl != nil)
                ? CoffeeImageURLs(thumb: thumbUrl ?? "", display: displayUrl ?? "", ocr: nil)
                : nil,
            brewTriedIds: brewTried,
            brewBestIds: brewBest
        )
    }
}
