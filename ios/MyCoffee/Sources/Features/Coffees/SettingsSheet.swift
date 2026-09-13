import SwiftUI

/// Settings behind the toolbar gear (PLAN.md §6): connection status plus
/// disconnect. No capture UI, no editor — read-and-review only (§6.7).
struct SettingsSheet: View {
    @EnvironmentObject private var config: AppConfig
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
        }
    }

    private func refreshStatus() async {
        do {
            let client = try APIClient(config: config)
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
        do {
            let client = try APIClient(config: config)
            whatsnewLive = try await client.whatsNew().live
        } catch {
            whatsnewLive = []
        }
    }
}
