import Foundation

/// Abstracts where a `CoffeeIndex` comes from. The real network-backed
/// implementation — delta sync against `/api/snapshot` — lands with backlog
/// item #22, which needs backend endpoints that don't exist yet (#21).
/// Until then, `SampleCoffeeRepository` is the only conformer, so the UX lane
/// can build every screen against realistic, varied fixture data rather than
/// blocking on the backend.
protocol CoffeeRepository: Sendable {
    /// The most recently loaded index, without triggering a fetch.
    func currentIndex() async -> CoffeeIndex

    /// Loads (or reloads) the index and returns it.
    func refresh() async throws -> CoffeeIndex
}
