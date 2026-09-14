import Foundation

/// Wire shape for `GET /api/whatsnew` (backend `routes/whatsnew.js`, PLAN.md
/// §13): `{ live: [{title, detail, area}], plan: { byLane: {backend:[…],
/// data:[…], ios:[…]}, needsApproval: [{title, detail}] } }`. Curated prose,
/// not a live backlog dump — decode leniently anyway (same all-or-nothing
/// guard the snapshot/review feeds use) so one malformed row never blanks the
/// whole screen.
struct WhatsNewResponseDTO: Decodable {
    let live: [WhatsNewItemDTO]
    let plan: WhatsNewPlanDTO

    private enum CodingKeys: String, CodingKey { case live, plan }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        live = try c.decode([FailableDecodable<WhatsNewItemDTO>].self, forKey: .live).compactMap(\.value)
        plan = try c.decode(WhatsNewPlanDTO.self, forKey: .plan)
    }
}

struct WhatsNewPlanDTO: Decodable {
    let byLane: [String: [WhatsNewItemDTO]]
    let needsApproval: [WhatsNewItemDTO]

    private enum CodingKeys: String, CodingKey { case byLane, needsApproval }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawByLane = try c.decodeIfPresent([String: [FailableDecodable<WhatsNewItemDTO>]].self, forKey: .byLane) ?? [:]
        byLane = rawByLane.mapValues { $0.compactMap(\.value) }
        needsApproval = try c.decode([FailableDecodable<WhatsNewItemDTO>].self, forKey: .needsApproval).compactMap(\.value)
    }
}

/// One card: `title` + `detail` always present; `area` (a lane tag, e.g.
/// `"backend"`/`"data"`/`"ios"`) is only sent on `live` items, `nil` on
/// `plan` items (the plan is already grouped by lane via `byLane`'s keys).
struct WhatsNewItemDTO: Decodable {
    let title: String
    let detail: String
    let area: String?
}

/// #201 — `GET|POST /api/whatsnew/seen`. The server treats keys as opaque
/// strings (migration 036: `whatsnew_seen (entry_key PK, seen_at)`, no
/// `user_id` — MyCoffee has one shared INGEST_TOKEN and therefore one seen
/// set), so there is nothing to decode but the array itself.
struct WhatsNewSeenResponseDTO: Decodable {
    let seen: [String]
}

struct WhatsNewSeenRequestDTO: Encodable {
    let key: String
    let seen: Bool
}
