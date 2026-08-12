import SwiftUI

/// Settings behind the toolbar gear (PLAN.md §6): connection status plus
/// disconnect. No capture UI, no editor — read-and-review only (§6.7).
struct SettingsSheet: View {
    @EnvironmentObject private var config: AppConfig
    @Environment(\.dismiss) private var dismiss

    @State private var statusText = "Checking…"
    @State private var isHealthy = false

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
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("What's New", systemImage: Symbols.whatsNew)
                    }
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
}
