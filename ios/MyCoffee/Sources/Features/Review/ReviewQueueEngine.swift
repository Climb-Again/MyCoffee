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
/// `[ReviewTask]` (PLAN.md §6.5). **Not wired to the real backend yet** —
/// `CoffeeStore`/`APIClient` (shell-owned) expose no `GET /api/review` /
/// `POST /api/review/:id` / `POST /api/review/rules` methods today (same gap
/// class as #28's flagged `loadBrief()`), so every action here only mutates
/// local state; nothing round-trips through the mutation outbox. Flagged in
/// `status/ios-ux.md` and claimed in both lane files rather than duplicating
/// networking plumbing inside `Features` — see that file for the exact
/// surface being requested.
@MainActor
final class ReviewQueueEngine: ObservableObject {
    @Published private(set) var openTasks: [ReviewTask]
    @Published private(set) var deferredIDs: [Int] = []
    @Published private(set) var expandedGroupKeys: Set<String> = []
    @Published private(set) var createdRules: [ReviewRule] = []
    @Published private(set) var toast: ReviewToast?

    private var undoStack: [UndoSnapshot] = []
    private var toastToken = 0
    let initialTotal: Int

    init(tasks: [ReviewTask] = ReviewSampleData.tasks) {
        self.openTasks = tasks
        self.initialTotal = tasks.count
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
