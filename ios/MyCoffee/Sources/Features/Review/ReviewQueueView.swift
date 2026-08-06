import SwiftUI

/// The Review tab (PLAN.md §6.5), replacing `ReviewPlaceholderView` now that
/// #22 (sync) and #24 (adjudication backend) have both landed. Loads the real
/// queue from `GET /api/review` on appear and persists each accept/dismiss
/// through `CoffeeStore.resolveReview`/`.dismissReview` (durable via
/// `MutationOutbox` — survives offline/app restart, unlike a raw `APIClient`
/// call); the sample fixtures survive only as `#Preview` fodder.
struct ReviewQueueView: View {
    @EnvironmentObject private var store: CoffeeStore
    @StateObject private var engine = ReviewQueueEngine(tasks: [])
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("Loading review queue…")
                } else if let loadError, engine.isEmpty {
                    errorState(loadError)
                } else if engine.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { engine.undo() }
                    } label: {
                        Image(systemName: Symbols.reviewUndo)
                    }
                    .disabled(!engine.canUndo)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = engine.toast {
                    toastView(toast)
                }
            }
            .animation(.default, value: engine.toast)
            .animation(.default, value: engine.currentEntry?.id)
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let client = try await APIClient(config: AppConfig.shared)
            let feed = try await client.reviewFeed()
            engine.load(feed.items.compactMap(ReviewTask.init(dto:)))
            // Durable through the outbox — survives offline/app restart,
            // unlike a raw fire-and-forget `APIClient` call.
            engine.onAccept = { task, value in
                store.resolveReview(taskId: task.id, value: value)
            }
            engine.onDismiss = { task in
                store.dismissReview(taskId: task.id)
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

    private var content: some View {
        VStack(spacing: 16) {
            progressBar
            if let entry = engine.currentEntry {
                cardView(for: entry)
                    .id(entry.id)
                    .padding(.horizontal)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            Spacer()
        }
        .padding(.top, 8)
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

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(engine.progressDone) of \(engine.progressTotal)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !engine.createdRules.isEmpty {
                    Label("\(engine.createdRules.count) rule\(engine.createdRules.count == 1 ? "" : "s")", systemImage: Symbols.reviewRule)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(engine.progressDone), total: Double(max(engine.progressTotal, 1)))
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "All caught up",
            systemImage: Symbols.reviewEmpty,
            description: Text("No coffees need a look right now.")
        )
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
