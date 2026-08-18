import Foundation

extension ReviewTask {
    /// Grouping key for both batch collapsing and rule-wide acceptance.
    var batchKey: String { "\(field.rawValue)|\(rawValue.reviewGroupingKey)" }
}

/// One prior decision, kept just long enough to undo it (PLAN.md §6.5: "toast
/// Undo (5 s) | 20-deep undo stack"). `indices` are best-effort reinsertion
/// points in `openTasks` at the moment of removal — undo restores the tasks
/// and any rule created alongside them; it does not try to reproduce the
/// exact prior queue position beyond that.
private struct UndoSnapshot {
    let tasks: [ReviewTask]
    let indices: [Int]
    let createdRule: ReviewRule?
}

struct ReviewToast: Equatable {
    let text: String
}

/// Drives the review queue's ordering and gestures against a plain
/// `[ReviewTask]` (PLAN.md §6.5). Wired to the real backend by `ReviewQueueView`:
/// it `load()`s the tasks from `GET /api/review` and sets `onAccept`/`onDismiss`
/// so an accept (`POST /api/review/:id` with the picked value) and a "not on the
/// bag" dismiss both round-trip. Ordering/undo/defer stay purely local — the
/// backend records the resolution the moment it's accepted; undo only restores
/// the card locally within the 5 s window and does not un-resolve server-side.
@MainActor
final class ReviewQueueEngine: ObservableObject {
    @Published private(set) var openTasks: [ReviewTask]
    @Published private(set) var deferredIDs: [Int] = []
    @Published private(set) var expandedGroupKeys: Set<String> = []
    @Published private(set) var createdRules: [ReviewRule] = []
    @Published private(set) var toast: ReviewToast?

    private var undoStack: [UndoSnapshot] = []
    private var toastToken = 0
    private(set) var initialTotal: Int

    /// Persistence hooks, injected by the view once it has an `APIClient`.
    /// The queue advances optimistically, but the hook is now **awaited and
    /// confirmed**: it returns whether the save round-tripped, and a `false`
    /// puts the item back in the queue (#66) — so a partial review session
    /// never silently loses accepts (the old fire-and-forget hook only
    /// persisted reliably once a later full sync flushed the outbox, i.e.
    /// "saves only when you finish all"). Returning `true` when nil keeps
    /// previews (no injected hook) behaving as before.
    var onAccept: ((ReviewTask, String) async -> Bool)?
    var onDismiss: ((ReviewTask) async -> Bool)?

    init(tasks: [ReviewTask] = ReviewSampleData.tasks) {
        self.openTasks = tasks
        self.initialTotal = tasks.count
    }

    /// Replace the queue with a freshly-fetched set of tasks, resetting the
    /// progress denominator and clearing any prior session's undo/defer state.
    func load(_ tasks: [ReviewTask]) {
        openTasks = tasks
        initialTotal = tasks.count
        deferredIDs = []
        expandedGroupKeys = []
        createdRules = []
        undoStack = []
        toast = nil
    }

    var progressDone: Int { initialTotal - openTasks.count }
    var progressTotal: Int { initialTotal }
    var canUndo: Bool { !undoStack.isEmpty }
    var isEmpty: Bool { queueEntries.isEmpty }

    /// Batch cards first (largest first), then per-coffee groups ordered by
    /// fewest open fields first, then tasks deferred by a left-swipe at the
    /// very back (PLAN.md §6.5).
    var queueEntries: [ReviewQueueEntry] {
        let deferredSet = Set(deferredIDs)
        let active = openTasks.filter { !deferredSet.contains($0.id) }

        var groups: [String: [ReviewTask]] = [:]
        var groupOrder: [String] = []
        for task in active {
            let key = task.batchKey
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(task)
        }

        var batchEntries: [ReviewBatchGroup] = []
        var singleTasks: [ReviewTask] = []
        for key in groupOrder {
            let tasksInGroup = groups[key] ?? []
            if tasksInGroup.count >= 8, !expandedGroupKeys.contains(key), let first = tasksInGroup.first {
                let topCandidate = first.candidates.first ?? ReviewCandidate(value: first.rawValue, hint: nil)
                batchEntries.append(ReviewBatchGroup(field: first.field, rawValue: first.rawValue, topCandidate: topCandidate, tasks: tasksInGroup))
            } else {
                singleTasks.append(contentsOf: tasksInGroup)
            }
        }
        batchEntries.sort { $0.tasks.count > $1.tasks.count }

        var coffeeGroups: [String: [ReviewTask]] = [:]
        var coffeeOrder: [String] = []
        for task in singleTasks {
            let key = task.coffeeId ?? task.photoId
            if coffeeGroups[key] == nil { coffeeOrder.append(key) }
            coffeeGroups[key, default: []].append(task)
        }
        let orderedCoffeeKeys = coffeeOrder.sorted { (coffeeGroups[$0]?.count ?? 0) < (coffeeGroups[$1]?.count ?? 0) }
        let orderedSingles = orderedCoffeeKeys.flatMap { coffeeGroups[$0] ?? [] }

        let deferredTasks = deferredIDs.compactMap { id in openTasks.first { $0.id == id } }

        return batchEntries.map { .batch($0) } + orderedSingles.map { .single($0) } + deferredTasks.map { .single($0) }
    }

    var currentEntry: ReviewQueueEntry? { queueEntries.first }

    // MARK: - Actions

    /// Swipe right / tap a chip: accept, advance immediately, no confirm step.
    func accept(_ task: ReviewTask, value: String) {
        guard let index = openTasks.firstIndex(where: { $0.id == task.id }) else { return }
        openTasks.remove(at: index)
        deferredIDs.removeAll { $0 == task.id }
        pushUndo(UndoSnapshot(tasks: [task], indices: [index], createdRule: nil))
        showToast("\(task.field.label) → \(value)")
        confirmSave(task, at: index) { [onAccept] in await onAccept?(task, value) ?? true }
    }

    /// Long-press a chip: accept **and** create a mapping rule applied to
    /// every remaining task sharing this `(field, rawValue)` — including ones
    /// not currently grouped into a visible batch card. Falls back to a plain
    /// accept for fields with no alias table server-side.
    func acceptWithRule(_ task: ReviewTask, value: String) {
        guard task.field.aliasKind != nil else {
            accept(task, value: value)
            return
        }
        acceptAll(matching: task.batchKey, field: task.field, rawValue: task.rawValue, value: value)
    }

    /// "Accept all N" on a batch card — the same bulk-and-remember behaviour
    /// as a long-press, applied to the whole group at once.
    func acceptBatch(_ group: ReviewBatchGroup) {
        acceptAll(matching: group.id, field: group.field, rawValue: group.rawValue, value: group.topCandidate.value)
    }

    /// "Review individually" — permanently un-collapses this group for the
    /// rest of the session, even if it's still ≥8 strong.
    func reviewIndividually(_ group: ReviewBatchGroup) {
        expandedGroupKeys.insert(group.id)
    }

    /// Swipe left: skip to the very back of the whole queue, not just this
    /// task's group.
    func skipToBack(_ task: ReviewTask) {
        deferredIDs.removeAll { $0 == task.id }
        deferredIDs.append(task.id)
    }

    /// Swipe down: not on the bag — stop asking forever (this session).
    func markNotPresent(_ task: ReviewTask) {
        guard let index = openTasks.firstIndex(where: { $0.id == task.id }) else { return }
        openTasks.remove(at: index)
        deferredIDs.removeAll { $0 == task.id }
        pushUndo(UndoSnapshot(tasks: [task], indices: [index], createdRule: nil))
        showToast("Marked not present")
        confirmSave(task, at: index) { [onDismiss] in await onDismiss?(task) ?? true }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        for (undoneTask, index) in zip(last.tasks, last.indices) {
            let insertAt = min(max(index, 0), openTasks.count)
            openTasks.insert(undoneTask, at: insertAt)
        }
        if let rule = last.createdRule {
            createdRules.removeAll { $0.id == rule.id }
        }
        toast = nil
    }

    // MARK: - Private

    private func acceptAll(matching key: String, field: ReviewField, rawValue: String, value: String) {
        let matches = openTasks.enumerated().filter { $0.element.batchKey == key }
        guard !matches.isEmpty else { return }
        let removedTasks = matches.map(\.element)
        for index in matches.map(\.offset).sorted(by: >) {
            openTasks.remove(at: index)
        }
        let removedIDs = Set(removedTasks.map(\.id))
        deferredIDs.removeAll { removedIDs.contains($0) }

        // Each accepted task resolves independently server-side (the rule is a
        // client-side convenience; the backend has no bulk-rule endpoint wired),
        // and each is confirmed — a failed one comes back to the queue (#66).
        for (removed, idx) in zip(removedTasks, matches.map(\.offset)) {
            confirmSave(removed, at: idx) { [onAccept] in await onAccept?(removed, value) ?? true }
        }

        var createdRule: ReviewRule?
        if let kind = field.aliasKind {
            let rule = ReviewRule(kind: kind, rawValue: rawValue, canonicalValue: value, appliedCount: removedTasks.count)
            createdRules.append(rule)
            createdRule = rule
        }
        pushUndo(UndoSnapshot(tasks: removedTasks, indices: matches.map(\.offset), createdRule: createdRule))

        let plural = removedTasks.count == 1 ? "coffee" : "coffees"
        showToast("\(removedTasks.count) \(plural): \"\(rawValue)\" → \(value)")
    }

    /// Await the injected save after the optimistic removal; if it doesn't
    /// round-trip, put the task back where it was and warn — so no review step
    /// is ever silently lost (#66). No-op hook (previews) reports success.
    private func confirmSave(_ task: ReviewTask, at index: Int, _ save: @escaping () async -> Bool) {
        Task { [weak self] in
            let ok = await save()
            guard let self, !ok else { return }
            self.restore(task, at: index)
        }
    }

    private func restore(_ task: ReviewTask, at index: Int) {
        guard !openTasks.contains(where: { $0.id == task.id }) else { return }
        let insertAt = min(max(index, 0), openTasks.count)
        openTasks.insert(task, at: insertAt)
        // Drop the now-stale undo entry so an Undo can't double-insert it.
        undoStack.removeAll { $0.tasks.contains { $0.id == task.id } }
        showToast("⚠︎ Couldn't save \(task.field.label) — it's back in the queue")
    }

    private func pushUndo(_ snapshot: UndoSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > 20 {
            undoStack.removeFirst(undoStack.count - 20)
        }
    }

    private func showToast(_ message: String) {
        toastToken += 1
        let token = toastToken
        toast = ReviewToast(text: message)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard self.toastToken == token else { return }
            self.toast = nil
        }
    }
}
