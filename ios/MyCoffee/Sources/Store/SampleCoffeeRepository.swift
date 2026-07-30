import Foundation

/// Serves `SampleData` as a `CoffeeIndex`. The default repository until #22
/// wires up the real sync engine — swapping it out is a one-line change in
/// `CoffeeStore`.
actor SampleCoffeeRepository: CoffeeRepository {
    private let index: CoffeeIndex

    init() {
        index = CoffeeIndex(coffees: SampleData.coffees, vocabulary: SampleData.vocabulary)
    }

    func currentIndex() async -> CoffeeIndex { index }

    func refresh() async throws -> CoffeeIndex { index }
}
