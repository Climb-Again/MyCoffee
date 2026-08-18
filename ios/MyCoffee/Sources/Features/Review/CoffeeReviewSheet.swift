import SwiftUI

/// Review the open items for a single coffee, launched from the "Needs review"
/// marker on its detail page. Reuses the same `ReviewQueueEngine` +
/// `ReviewCardStack` as the Review tab, but seeded only with this coffee's
/// tasks (the feed filtered by `coffeeId`). Resolving/dismissing persists
/// through `CoffeeStore`'s `MutationOutbox` — same durable path as the Review
/// tab, not a fire-and-forget `APIClient` call; `onFinished` lets the detail
/// page re-fetch so the badge and the newly-decided fields update.
struct CoffeeReviewSheet: View {
    let coffeeId: String
    var onFinished: () -> Void = {}

    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = ReviewQueueEngine(tasks: [])
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var didResolveAny = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if let loadError, engine.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't load review", systemImage: Symbols.reviewPhotoMissing)
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else if engine.isEmpty {
                    ContentUnavailableView(
                        "All set",
                        systemImage: Symbols.reviewEmpty,
                        description: Text("Nothing left to review for this coffee.")
                    )
                } else {
                    ReviewCardStack(engine: engine)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { finish() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = engine.isEmpty
        loadError = nil
        do {
            let client = try await APIClient(config: AppConfig.shared)
            let feed = try await client.reviewFeed()
            ReviewFeedCache.shared.adopt(feed)
            let tasks = feed.items
                .compactMap(ReviewTask.init(dto:))
                .filter { $0.coffeeId == coffeeId }
            engine.load(tasks)
            engine.onAccept = { task, value in
                didResolveAny = true
                return await store.resolveReview(taskId: task.id, value: value)
            }
            engine.onDismiss = { task in
                didResolveAny = true
                return await store.dismissReview(taskId: task.id)
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func finish() {
        if didResolveAny { onFinished() }
        dismiss()
    }
}
