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

    func setRotation(coffeeId: String, quarterTurns: Int) async throws -> CoffeeIndex {
        let updated = index.coffees.map { coffee in
            coffee.id == coffeeId ? coffee.withRotation(quarterTurns) : coffee
        }
        index = CoffeeIndex(coffees: updated, vocabulary: index.vocabulary, searchTexts: index.searchTexts)
        return index
    }

    // Same reasoning: canonicalizing an edit's raw value the way the backend
    // does isn't fixture logic worth duplicating here, so previews see no
    // change rather than a guessed-at one.
    func editField(coffeeId: String, field: String, value: String) async throws -> Coffee {
        throw APIClient.APIError.notConfigured
    }

    func editFields(coffeeId: String, edits: [CoffeeFieldEdit]) async throws -> Coffee {
        throw APIClient.APIError.notConfigured
    }

    // No live backend to run the extraction ensemble against in previews —
    // same reasoning as `editField`/`editFields` above.
    func uploadPhotos(_ images: [Data], fullText: String) async throws -> [String] {
        throw APIClient.APIError.notConfigured
    }

    func extractDraft(photoIds: [String]) async throws -> ExtractedDraft {
        throw APIClient.APIError.notConfigured
    }

    // No live backend to evaluate against in previews — same reasoning as
    // `extractDraft`.
    func evaluateCoffee(photoIds: [String]) async throws -> EvaluateResult {
        throw APIClient.APIError.notConfigured
    }

    func createCoffee(photoIds: [String], fields: [CoffeeFieldEdit]) async throws -> Coffee {
        throw APIClient.APIError.notConfigured
    }

    // Same reasoning: no live backend to quick-create against in previews.
    func quickCreateCoffee(photoIds: [String]) async throws -> Coffee {
        throw APIClient.APIError.notConfigured
    }

    // Real, local tri-state machine (mirrors `SyncEngine`'s optimistic path,
    // minus the outbox) so Brew lab previews (#157) are actually tappable,
    // not just a static fixture.
    func setBrewState(coffeeId: String, optionId: Int, state: BrewTrialState) async -> CoffeeIndex {
        guard let coffee = index.coffee(id: coffeeId), let option = index.vocabulary.brewOptions[optionId] else {
            return index
        }
        var tried = Set(coffee.triedBrewOptionIds)
        var best = Set(coffee.bestBrewOptionIds)
        switch state {
        case .untried:
            tried.remove(option.id)
            best.remove(option.id)
        case .tried:
            tried.insert(option.id)
            best.remove(option.id)
        case .best:
            tried.insert(option.id)
            for id in best where id != option.id && index.vocabulary.brewOptions[id]?.kind == option.kind {
                best.remove(id)
            }
            best.insert(option.id)
        }
        let updated = index.coffees.map { c in
            c.id == coffeeId ? c.withBrew(tried: tried.sorted(), best: best.sorted()) : c
        }
        index = CoffeeIndex(coffees: updated, vocabulary: index.vocabulary, searchTexts: index.searchTexts)
        return index
    }

    // No live backend to create/rename a catalogue option against in
    // previews — same reasoning as `editField`.
    func createBrewOption(
        kind: BrewKind, label: String?, detail: String?, valueNum: Double?, recipe: BrewRecipeSpec?
    ) async throws -> BrewOption {
        throw APIClient.APIError.notConfigured
    }

    func updateBrewOption(id: Int, patch: BrewOptionPatch) async throws -> BrewOption {
        throw APIClient.APIError.notConfigured
    }
}
