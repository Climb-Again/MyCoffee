import SwiftUI

/// One row of `FactRowsCard`. Missing fields **omit their row entirely** —
/// never "N/A" (PLAN.md §6.3) — so callers only construct a `FactRow` when
/// the value exists; there is no "empty" rendering state here at all.
struct FactRow: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

/// A card of `FactRow`s, itself omitted by the caller when `rows` is empty.
struct FactRowsCard: View {
    let rows: [FactRow]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                row
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
