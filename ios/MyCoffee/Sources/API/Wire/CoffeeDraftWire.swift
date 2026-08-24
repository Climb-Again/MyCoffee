import Foundation

/// Wire shapes for the Add Coffee wizard (PLAN.md §6.8, backend #75, iOS shell
/// #76): photo registration/upload, the light-extraction draft, and the final
/// create. `Models/CoffeeDraft.swift` holds the domain types #77's confirm
/// screen actually reads; these are the raw decode targets.

/// `POST /api/photos/manifest` response — one entry per submitted photo, in
/// the same order they were sent (`routes/photos.js` pushes results in a
/// plain loop over `entries`).
struct PhotoManifestResponseDTO: Decodable {
    let ok: Bool
    let results: [PhotoManifestResultDTO]
}

struct PhotoManifestResultDTO: Decodable {
    let sourceId: String
    let photoId: String
    let need: String // "none" | "image" — "image" is expected here; the wizard always uploads a fresh photo
}

/// `POST /api/coffees/extract` response — one entry per field the light
/// ensemble resolved, keyed by the same camelCase client field name the
/// generic edit endpoint (#40/#41) and review queue already use
/// (`originCountry`, `roaster`, `farm`, `profile`, `altitude`, `weight`,
/// `price`, `roasterCountry`, `rating`, `roastedOn`).
struct ExtractedDraftDTO: Decodable {
    let fields: [String: ExtractedDraftFieldDTO]
    let spentUsd: Double?
}

struct ExtractedDraftFieldDTO: Decodable {
    let value: String?
    let confidence: Double?
    let decision: String? // "absent" | "accepted" | "split"
    let candidates: [ExtractedDraftCandidateDTO]
    let evidence: String?
}

struct ExtractedDraftCandidateDTO: Decodable {
    let value: String
}

/// `POST /api/coffees` response — the new coffee's public id plus the fields
/// actually applied. The wizard re-fetches full detail via that id rather than
/// trusting this echo for display (same "server round-trip wins" shape
/// `editField` uses).
struct CreateCoffeeResponseDTO: Decodable {
    let id: String
    let fields: [CreateCoffeeFieldResultDTO]
}

struct CreateCoffeeFieldResultDTO: Decodable {
    let field: String
    let value: String
}
