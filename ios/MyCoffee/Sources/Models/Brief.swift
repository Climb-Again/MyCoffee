import Foundation

/// One `briefs` row (`GET /api/brief`) — the Vertex-generated "This month"
/// editorial section PLAN.md §6.4 asks Insights to reuse. `nil` until the
/// backend has actually generated one; the route currently returns a
/// placeholder `message` in that case (`APIClient.brief()` just drops it).
struct Brief: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let body: String
    let generatedAt: Date
}
