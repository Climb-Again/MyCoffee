import SwiftUI

/// One row of `FactRowsList`. Missing fields **omit their row entirely** —
/// never "N/A" (PLAN.md §6.3) — so callers only construct a `FactRow` when
/// the value exists; there is no "empty" rendering state here at all.
///
/// 2a redesign (`#88`, `design/coffees_redesign/README.md` §Screen 2): plain
/// label/value pair, no icon, no rule — the icon + grey-card treatment this
/// replaced is gone (the price rows it used to include moved to their own
/// price block).
struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.neutral700)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: Theme.Weight.semibold))
                .foregroundStyle(Theme.Colors.text)
        }
    }
}

/// A stack of `FactRow`s, itself omitted by the caller when `rows` is empty.
/// No card background, no rules between rows — 9pt gaps only.
struct FactRowsList: View {
    let rows: [FactRow]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                row
            }
        }
    }
}
