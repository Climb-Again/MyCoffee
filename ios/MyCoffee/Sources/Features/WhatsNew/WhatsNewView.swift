import SwiftUI

/// PLAN.md §13 / #47 — reachable from Settings (a "What's New" row), not a 4th
/// tab, so the tab bar stays at Coffees/Insights/Review. Segmented Live/Plan;
/// read-only in v1 — it informs, it doesn't approve inline. Backend-served
/// (`GET /api/whatsnew`, #45/#46) so the content updates without a TestFlight
/// build.
struct WhatsNewView: View {
    /// #205(a): Live · Done · Plan, matching Radu's reference screenshot.
    ///
    /// `Done` lists the Live entries he has already checked off — the same
    /// items, the other side of the tick. It is NOT a fourth backend section:
    /// `/api/whatsnew` has `live` and `plan` and nothing else, and "done" is a
    /// per-person fact the server has no opinion about (it lives in
    /// `WhatsNewSeenStore`). Deriving it keeps one source of truth for the
    /// tick, which is the whole reason #200 built a store rather than a flag
    /// per view.
    private enum Segment: String, CaseIterable, Identifiable {
        case live = "Live"
        case done = "Done"
        case plan = "Plan"
        var id: String { rawValue }
    }

    /// #205(b): the second control row — All · ✓ · ☐ — filtering the current
    /// segment by seen state.
    private enum SeenFilter: String, CaseIterable, Identifiable {
        case all
        case checked
        case unchecked
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .checked: return "✓"
            case .unchecked: return "☐"
            }
        }

        func keep(_ isSeen: Bool) -> Bool {
            switch self {
            case .all: return true
            case .checked: return isSeen
            case .unchecked: return !isSeen
            }
        }
    }

    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: CoffeeStore
    @ObservedObject private var seenStore = WhatsNewSeenStore.shared
    @State private var segment: Segment = .live
    @State private var seenFilter: SeenFilter = .all
    @State private var response: WhatsNewResponseDTO?
    @State private var loadError: String?
    @State private var isLoading = true

    private var liveUnseen: Int {
        guard let response else { return 0 }
        return seenStore.unseenCount(in: response.live)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { segment in
                    // Show the unseen count next to Live so opening the sheet
                    // doesn't require reading the whole list to see if there's
                    // anything new — matches the badge on the Settings row.
                    if segment == .live, liveUnseen > 0 {
                        Text("Live · \(liveUnseen) new").tag(segment)
                    } else {
                        Text(segment.rawValue).tag(segment)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            // #205(b): the seen-state row. Hidden on Done, where every card is
            // checked by construction — a filter whose only non-empty option is
            // "checked" is a control that cannot do anything.
            if segment != .done {
                Picker("Seen", selection: $seenFilter) {
                    ForEach(SeenFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Filter by checked state")
            }

            content
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let response, liveUnseen > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all seen") {
                        seenStore.markSeen(response.live)
                    }
                }
            }
        }
        .task { await load() }
        // #201: hydrate the tick state from the server so the phone reflects
        // what was checked on the iPad. Separate from `load()` on purpose —
        // the content and the seen set fail independently, and a backend that
        // is down for one must not blank the other.
        .task { seenStore.startSync(config: config) }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let response {
            switch segment {
            case .live:
                // Live shows what is NOT done, plus whatever the seen filter
                // asks for; Done is the checked complement. Together they
                // partition `response.live`, so nothing can hide in a gap.
                liveList(filtered(response.live, unseenOnly: true), emptyTitle: "Nothing live yet")
            case .done:
                liveList(response.live.filter { seenStore.isSeen($0) }, emptyTitle: "Nothing checked off yet")
            case .plan:
                planList(response.plan)
            }
        } else {
            ContentUnavailableView {
                Label("Couldn't load", systemImage: Symbols.whatsNewUnavailable)
            } description: {
                Text(loadError ?? "Unknown error")
            } actions: {
                Button("Try again") { Task { await load() } }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        guard let client = await store.makeAPIClient() else {
            loadError = "Couldn't connect"
            isLoading = false
            return
        }
        do {
            response = try await client.whatsNew()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Applies the seen-state filter. `unseenOnly` is the Live segment's own
    /// rule (a checked item belongs under Done), applied BEFORE the filter so
    /// picking ✓ on Live shows nothing rather than duplicating Done.
    private func filtered(_ items: [WhatsNewItemDTO], unseenOnly: Bool) -> [WhatsNewItemDTO] {
        items.filter { item in
            let isSeen = seenStore.isSeen(item)
            if unseenOnly && isSeen && seenFilter != .checked { return false }
            return seenFilter.keep(isSeen)
        }
    }

    @ViewBuilder
    private func liveList(_ items: [WhatsNewItemDTO], emptyTitle: String) -> some View {
        if items.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: Symbols.whatsNewEmpty)
        } else {
            List(items, id: \.title) { item in
                WhatsNewCard(item: item)
                    .listRowSeparator(.hidden)
                    // #205(c): the screenshot's orange trailing swipe. The
                    // inverse of tapping the circle, routed through the SAME
                    // store (`markNotSeen`, idempotent) so there is still one
                    // definition of "done" — a second path that wrote its own
                    // state is exactly how the checkbox and the badge would
                    // start disagreeing.
                    .swipeActions(edge: .trailing) {
                        if seenStore.isSeen(item) {
                            Button {
                                seenStore.markNotSeen(item)
                            } label: {
                                Label("Not done", systemImage: Symbols.whatsNewNotDone)
                            }
                            .tint(.orange)
                        }
                    }
            }
            .listStyle(.plain)
        }
    }

    // Fixed lane order/labels rather than sorting `byLane`'s keys — a stable,
    // product-meaningful order (Backend, Data, iOS) beats alphabetical.
    private static let laneOrder: [(key: String, title: String)] = [
        ("backend", "Backend"),
        ("data", "Data"),
        ("ios", "iOS"),
    ]

    @ViewBuilder
    private func planList(_ plan: WhatsNewPlanDTO) -> some View {
        let laneSections = Self.laneOrder.filter { !(plan.byLane[$0.key]?.isEmpty ?? true) }
        if plan.needsApproval.isEmpty && laneSections.isEmpty {
            ContentUnavailableView("Nothing planned right now", systemImage: Symbols.whatsNewEmpty)
        } else {
            List {
                if !plan.needsApproval.isEmpty {
                    Section("Needs your approval") {
                        ForEach(plan.needsApproval, id: \.title) { item in
                            WhatsNewCard(item: item)
                        }
                    }
                }
                ForEach(laneSections, id: \.key) { lane in
                    Section(lane.title) {
                        ForEach(plan.byLane[lane.key] ?? [], id: \.title) { item in
                            WhatsNewCard(item: item)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

/// One feature card: title + one-line detail + an optional area chip. `area`
/// is only ever sent on `live` items (`WhatsNewItemDTO`'s own doc comment) —
/// the plan side is already grouped by lane via `byLane`'s section titles.
/// The leading circle is a check-off toggle (#200): tap marks the entry seen
/// so the badge on the Settings row drops. Seen title dims + strikes through
/// so the eye can skip to what's new without hunting for the empty circle.
private struct WhatsNewCard: View {
    let item: WhatsNewItemDTO
    @ObservedObject private var seenStore = WhatsNewSeenStore.shared

    private var isSeen: Bool { seenStore.isSeen(item) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                seenStore.toggle(item)
            } label: {
                Image(systemName: isSeen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSeen ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSeen ? "Mark unseen" : "Mark seen")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSeen ? .secondary : .primary)
                        .strikethrough(isSeen, color: .secondary)
                    Spacer(minLength: 8)
                    if let area = item.area {
                        AreaChip(area: area)
                    }
                }
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AreaChip: View {
    let area: String

    var body: some View {
        Text(area.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
