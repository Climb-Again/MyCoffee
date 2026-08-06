import Foundation

/// The real, network-backed `CoffeeRepository` (backlog #22) — `CoffeeStore`'s
/// default now that #21's backend endpoints exist. Delta-syncs against
/// `/api/snapshot` and persists to disk between launches via `SyncEngine`;
/// this type itself is just the `APIClient` plumbing, since `AppConfig`
/// (Keychain + `UserDefaults`) is `@MainActor` and this repository's methods
/// are called from actor/background contexts.
actor RemoteCoffeeRepository: CoffeeRepository {
    private let engine = SyncEngine()

    func currentIndex() async -> CoffeeIndex {
        await engine.currentIndex()
    }

    func refresh() async throws -> CoffeeIndex {
        let client = try await APIClient(config: AppConfig.shared)
        return try await engine.sync(using: client)
    }

    func setFavorite(coffeeId: String, isFavorite: Bool) async -> CoffeeIndex {
        let client = try? await APIClient(config: AppConfig.shared)
        return await engine.setFavorite(coffeeId: coffeeId, isFavorite: isFavorite, client: client)
    }

    func loadDetail(coffeeId: String) async throws -> Coffee {
        let client = try await APIClient(config: AppConfig.shared)
        return try await engine.loadDetail(coffeeId: coffeeId, using: client)
    }

    func resolveReview(taskId: Int, value: String) async {
        let client = try? await APIClient(config: AppConfig.shared)
        await engine.resolveReview(taskId: taskId, value: value, client: client)
    }

    func dismissReview(taskId: Int) async {
        let client = try? await APIClient(config: AppConfig.shared)
        await engine.dismissReview(taskId: taskId, client: client)
    }
}
