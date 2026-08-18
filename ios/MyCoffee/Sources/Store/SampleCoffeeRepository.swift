import Foundation

/// Serves `SampleData` as a `CoffeeIndex` — for previews and any work that
/// wants realistic fixture data without a live backend. `RemoteCoffeeRepository`
/// is `CoffeeStore`'s default since #22.
actor SampleCoffeeRepository: CoffeeRepository {
    private var index: CoffeeIndex

    init() {
        index = CoffeeIndex(coffees: SampleData.coffees, vocabulary: SampleData.vocabulary)
    }

    func currentIndex() async -> CoffeeIndex { index }

    func refresh() async throws -> CoffeeIndex { index }

    func setFavorite(coffeeId: String, isFavorite: Bool) async -> CoffeeIndex {
        let updated = index.coffees.map { coffee in
            coffee.id == coffeeId ? coffee.withFavorite(isFavorite, setBy: "human") : coffee
        }
        index = CoffeeIndex(coffees: updated, vocabulary: index.vocabulary, searchTexts: index.searchTexts)
        return index
    }

    func loadDetail(coffeeId: String) async throws -> Coffee {
        guard let coffee = index.coffee(id: coffeeId) else {
            throw APIClient.APIError.http(status: 404, body: "coffee_not_found")
        }
        return coffee
    }

    // No live backend to enqueue against in previews — the sample fixture
    // has no review-task feed at all, so these are deliberate no-ops.
    func resolveReview(taskId: Int, value: String) async throws {}

    func dismissReview(taskId: Int) async throws {}

    // Same reasoning: canonicalizing an edit's raw value the way the backend
    // does isn't fixture logic worth duplicating here, so previews see no
    // change rather than a guessed-at one.
    func editField(coffeeId: String, field: String, value: String) async throws -> Coffee {
        throw APIClient.APIError.notConfigured
    }

    func editFields(coffeeId: String, edits: [CoffeeFieldEdit]) async throws -> Coffee {
        throw APIClient.APIError.notConfigured
    }
}
