import SwiftUI

/// PLAN.md §13 / #47 — reachable from Settings (a "What's New" row), not a 4th
/// tab, so the tab bar stays at Coffees/Insights/Review. Segmented Live/Plan;
/// read-only in v1 — it informs, it doesn't approve inline. Backend-served
/// (`GET /api/whatsnew`, #45/#46) so the content updates without a TestFlight
/// build.
struct WhatsNewView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case live = "Live"
        case plan = "Plan"
        var id: String { rawValue }
    }

    @EnvironmentObject private var config: AppConfig
    @State private var segment: Segment = .live
    @State private var response: WhatsNewResponseDTO?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            content
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let response {
            switch segment {
            case .live: liveList(response.live)
            case .plan: planList(response.plan)
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
        do {
            let client = try APIClient(config: config)
            response = try await client.whatsNew()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @ViewBuilder
    private func liveList(_ items: [WhatsNewItemDTO]) -> some View {
        if items.isEmpty {
            ContentUnavailableView("Nothing live yet", systemImage: Symbols.whatsNewEmpty)
        } else {
            List(items, id: \.title) { item in
                WhatsNewCard(item: item)
                    .listRowSeparator(.hidden)
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
private struct WhatsNewCard: View {
    let item: WhatsNewItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let area = item.area {
                    AreaChip(area: area)
                }
            }
            Text(item.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
