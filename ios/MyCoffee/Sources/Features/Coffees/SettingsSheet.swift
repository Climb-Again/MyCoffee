import SwiftUI

/// Settings behind the toolbar gear (PLAN.md §6): connection status plus
/// disconnect. No capture UI, no editor — read-and-review only (§6.7).
struct SettingsSheet: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var seenStore = WhatsNewSeenStore.shared

    @State private var statusText = "Checking…"
    @State private var isHealthy = false
    // Fetched here so the badge count is visible without opening the sheet
    // (that's the whole point of a badge). WhatsNewView refetches on its own
    // task — small, cached, and independent of this — so a stale count here
    // is worth strictly less than a round-trip we'd otherwise pay for.
    @State private var whatsnewLive: [WhatsNewItemDTO] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Backend") {
                    LabeledContent("URL", value: config.baseURL)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isHealthy ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    // #157: library-wide catalogue maintenance. Logging a brew
                    // happens on the coffee's own page; this is where you fix
                    // a name or retire a device.
                    NavigationLink {
                        BrewCatalogueView()
                    } label: {
                        Label("Brew catalogue", systemImage: Symbols.brewLab)
                    }
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("What's New", systemImage: Symbols.whatsNew)
                    }
                    .badge(seenStore.unseenCount(in: whatsnewLive))
                }
                // #192: #178(c)'s sync diagnostics, surfaced. The backend
                // status above answers "can I reach it right now"; this answers
                // "did the last sync actually work", which is a different
                // question and the one that was unanswerable before — a
                // pull-to-refresh that failed looked exactly like one that
                // succeeded and changed nothing.
                Section("Last sync") {
                    if let error = store.lastSyncError {
                        Label {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: Symbols.syncFailed)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let at = store.lastSyncedAt {
                        LabeledContent("Succeeded", value: at.formatted(date: .abbreviated, time: .shortened))
                    } else if store.lastSyncError == nil {
                        Text("No sync yet this launch")
                            .foregroundStyle(.secondary)
                    }
                    // #178(b): rows the snapshot carried that the library does
                    // not. Zero is the normal case and says so explicitly —
                    // a diagnostic that only appears when it is non-zero is one
                    // you never learn to trust.
                    LabeledContent("Rows dropped", value: "\(store.droppedRowCount)")
                }
                Section {
                    Button("Disconnect", role: .destructive) {
                        config.disconnect()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshStatus() }
            .task { await refreshWhatsNewBadge() }
            // #201: pull the seen set here too, not only inside the What's New
            // sheet — otherwise the badge would count entries already ticked
            // off on the iPad as new until you opened the sheet, which is the
            // one moment the badge exists to save you.
            .task { seenStore.startSync(config: config) }
        }
    }

    private func refreshStatus() async {
        guard let client = await store.makeAPIClient() else {
            isHealthy = false
            statusText = "Offline"
            return
        }
        do {
            let status = try await client.status()
            isHealthy = status.db
            statusText = status.db ? "Connected · DB healthy" : "Connected · DB unavailable"
        } catch {
            isHealthy = false
            statusText = "Offline"
        }
    }

    private func refreshWhatsNewBadge() async {
        // Non-blocking: a fetch failure leaves the badge at 0, which is honest
        // (we don't know how many are new) rather than showing a stale count.
        guard let client = await store.makeAPIClient() else {
            whatsnewLive = []
            return
        }
        do {
            whatsnewLive = try await client.whatsNew().live
        } catch {
            whatsnewLive = []
        }
    }
}
