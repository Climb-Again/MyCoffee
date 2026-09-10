import Foundation

/// The result of `POST /api/coffees/evaluate` (#106/#136) — a "fit with what
/// you buy" score for a bag Radu doesn't own yet. Ephemeral like
/// `ExtractedDraft`: nothing here is persisted or merged into `CoffeeIndex`.
struct EvaluateResult {
    let fields: EvaluateFields
    let evaluation: Evaluation
    let spentUsd: Double?

    init(dto: EvaluateResponseDTO) {
        fields = EvaluateFields(dto: dto.fields)
        evaluation = Evaluation(dto: dto.evaluation)
        spentUsd = dto.spentUsd
    }
}

/// The light ensemble's resolved fields, echoed back for display.
struct EvaluateFields {
    let roasterId: Int?
    let originCountryIds: [Int]
    /// Resolved straight from the wire slug into the client's own enum — see
    /// `EvaluateFieldsDTO.profileId`'s doc for why this is safe despite the
    /// sibling fields staying opaque vocab ids.
    let profile: Profile?
    let roasterCountryId: Int?
    let pricePer100gEur: Double?

    init(dto: EvaluateFieldsDTO) {
        roasterId = dto.roasterId
        originCountryIds = dto.originCountryIds
        profile = dto.profileId.flatMap(Profile.init(rawValue:))
        roasterCountryId = dto.roasterCountryId
        pricePer100gEur = dto.pricePer100gEur
    }
}

/// The scored fit itself. `score` is only ever non-`nil` when `confidence`
/// is `.normal` **and** the value component could be computed — the backend
/// suppresses a headline number rather than inventing one under those two
/// gates (`backend/src/lib/scoring.js`'s `evaluateCoffee`).
struct Evaluation {
    /// Falls back to `.low` on an unrecognised string rather than trapping —
    /// this is a display-only field, and a future third confidence level
    /// shouldn't crash the wizard.
    enum Confidence: String {
        case low, normal
    }

    let score: Int?
    let confidence: Confidence
    let components: EvaluationComponents

    init(dto: EvaluationDTO) {
        score = dto.score
        confidence = Confidence(rawValue: dto.confidence) ?? .low
        components = EvaluationComponents(dto: dto.components)
    }
}

struct EvaluationComponents {
    let affinity: AffinityComponent
    /// `nil` when the draft's price band has fewer than the backend's
    /// minimum rated-and-priced peers to trust a verdict from — same
    /// suppression rule the on-device value meter (`ValueRating`) uses.
    let value: ValueComponent?
    let novelty: NoveltyComponent

    init(dto: EvaluationComponentsDTO) {
        affinity = AffinityComponent(score: dto.affinity.score, raw: dto.affinity.raw)
        value = dto.value.map {
            ValueComponent(score: $0.score, pillCount: $0.pillCount, band: $0.band, bandN: $0.bandN)
        }
        novelty = NoveltyComponent(isNewRoaster: dto.novelty.isNewRoaster, isNewOrigin: dto.novelty.isNewOrigin)
    }
}

/// Percentile rank (0–100) of the draft's blended origin/roaster/process/
/// roaster-country affinity among every rated coffee's own affinity.
struct AffinityComponent {
    let score: Int
    let raw: Double
}

/// The draft's standing within its own price band — `band`/`bandN` are
/// 1-indexed and the band's peer count, mirroring the on-device value
/// meter's quintiles but computed against the price-band mean rather than a
/// library-wide percentile (the backend has no rating for this coffee to
/// rank).
struct ValueComponent {
    let score: Int
    let pillCount: Int
    let band: Int
    let bandN: Int
}

struct NoveltyComponent {
    let isNewRoaster: Bool
    let isNewOrigin: Bool
}
