import SwiftUI

/// The scrollable "one card at a time" review surface, shared by the Review tab
/// and the per-coffee review sheet (`CoffeeReviewSheet`). Owns the progress
/// header (with an explicit **Back** button so a mis-tap is always recoverable)
/// and the current card inside a `ScrollView` — the card can be long now that
/// the full source text shows by default, and it must scroll without advancing
/// the queue.
struct ReviewCardStack: View {
    @ObservedObject var engine: ReviewQueueEngine

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                if let entry = engine.currentEntry {
                    cardView(for: entry)
                        .id(entry.id)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            if let toast = engine.toast {
                toastView(toast)
            }
        }
        .animation(.default, value: engine.toast)
        .animation(.default, value: engine.currentEntry?.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    withAnimation { engine.undo() }
                } label: {
                    Label("Back", systemImage: Symbols.reviewUndo)
                        .font(.subheadline.weight(.medium))
                }
                .disabled(!engine.canUndo)

                Spacer()

                Text("\(engine.progressDone) of \(engine.progressTotal)")
                    .font(.subheadline.weight(.semibold))

                if !engine.createdRules.isEmpty {
                    Label("\(engine.createdRules.count)", systemImage: Symbols.reviewRule)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(engine.progressDone), total: Double(max(engine.progressTotal, 1)))
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func cardView(for entry: ReviewQueueEntry) -> some View {
        switch entry {
        case let .batch(group):
            ReviewBatchCardView(
                group: group,
                onAcceptAll: { withAnimation { engine.acceptBatch(group) } },
                onReviewIndividually: { withAnimation { engine.reviewIndividually(group) } }
            )
        case let .single(task):
            ReviewCardView(
                task: task,
                onAccept: { value in withAnimation { engine.accept(task, value: value) } },
                onAcceptWithRule: { value in withAnimation { engine.acceptWithRule(task, value: value) } },
                onSkip: { withAnimation { engine.skipToBack(task) } },
                onNotPresent: { withAnimation { engine.markNotPresent(task) } }
            )
        }
    }

    private func toastView(_ toast: ReviewToast) -> some View {
        Text(toast.text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 24)
    }
}

/// The Review tab (PLAN.md §6.5). Loads the real queue from `GET /api/review`
/// on appear and persists each accept/dismiss through the engine's injected
/// hooks; the sample fixtures survive only as `#Preview` fodder.
struct ReviewQueueView: View {
    @EnvironmentObject private var store: CoffeeStore
    @StateObject private var engine = ReviewQueueEngine(tasks: [])
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading review queue…")
                } else if let loadError, engine.isEmpty {
                    errorState(loadError)
                } else if engine.isEmpty {
                    emptyState
                } else {
                    ReviewCardStack(engine: engine)
                }
            }
            .navigationTitle("Review")
            .task { await load() }
            .refreshable { await load() }
            // Keep the tab badge in lock-step with the queue as items clear.
            .onChange(of: engine.openTasks.count) { _, count in
                store.setReviewQueueCount(count)
            }
        }
    }

    private func load() async {
        isLoading = engine.isEmpty
        loadError = nil
        do {
            let client = try await APIClient(config: AppConfig.shared)
            let feed = try await client.reviewFeed()
            let tasks = feed.items.compactMap(ReviewTask.init(dto:))
            engine.load(tasks)
            store.setReviewQueueCount(tasks.count)
            // Fire-and-forget persistence; a failed call leaves the row open
            // server-side, which the next `load()` will surface again.
            engine.onAccept = { task, value in
                Task { try? await client.resolveReview(id: "\(task.id)", value: value) }
            }
            engine.onDismiss = { task in
                Task { try? await client.dismissReview(id: "\(task.id)") }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load review", systemImage: Symbols.reviewPhotoMissing)
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await load() } }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "All caught up",
            systemImage: Symbols.reviewEmpty,
            description: Text("No coffees need a look right now.")
        )
    }
}
