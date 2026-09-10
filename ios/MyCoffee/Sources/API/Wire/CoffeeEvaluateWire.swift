import Foundation

/// `POST /api/coffees/evaluate` response (#106/#136) — "Evaluate this coffee":
/// scores a bag Radu doesn't own yet against the rated corpus, using the same
/// light-extraction ensemble as `/api/coffees/extract`. Read-only: unlike
/// `/api/coffees`, nothing here is written.

struct EvaluateResponseDTO: Decodable {
    let fields: EvaluateFieldsDTO
    let evaluation: EvaluationDTO
    let spentUsd: Double?
}

/// The light ensemble's resolved fields, echoed back so the caller can show
/// what was recognised.
///
/// **`profileId` is a slug string** (`"washed"`, `"co_fermented"`, …)
/// matching `Profile.rawValue` exactly — **not** a numeric vocab id like
/// `roasterId`/`roasterCountryId`, despite the parallel naming. Verified by
/// reading, not guessing: `backend/src/routes/coffees.js`'s evaluate handler
/// sets `profileId = resolutions.profile?.value?.profileId`, and
/// `backend/src/lib/adjudicate.js`'s `denormalize('profile', …)` returns
/// `{ profileId: canonical.profileId, … }` where `canonical.profileId` is the
/// raw alias key from `normalize.js`'s `PROFILE_ALIASES` (`co_fermented`,
/// `anaerobic`, `natural`, `washed`, `experimental`) — the same five slugs
/// `Profile`'s cases use as their raw values. So this decodes straight into
/// `Profile(rawValue:)`, unlike the other four fields which stay opaque ids.
struct EvaluateFieldsDTO: Decodable {
    let roasterId: Int?
    let originCountryIds: [Int]
    let profileId: String?
    let roasterCountryId: Int?
    let pricePer100gEur: Double?
}

struct EvaluationDTO: Decodable {
    let score: Int?
    let confidence: String // "low" | "normal"
    let components: EvaluationComponentsDTO
}

struct EvaluationComponentsDTO: Decodable {
    let affinity: AffinityComponentDTO
    let value: ValueComponentDTO?
    let novelty: NoveltyComponentDTO
}

struct AffinityComponentDTO: Decodable {
    let score: Int
    let raw: Double
}

struct ValueComponentDTO: Decodable {
    let score: Int
    let pillCount: Int
    let band: Int
    let bandN: Int
}

struct NoveltyComponentDTO: Decodable {
    let isNewRoaster: Bool
    let isNewOrigin: Bool
}
