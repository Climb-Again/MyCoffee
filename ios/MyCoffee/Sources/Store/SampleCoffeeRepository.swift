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
}
