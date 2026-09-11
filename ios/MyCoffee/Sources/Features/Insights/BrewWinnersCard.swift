import SwiftUI

/// Insights → "Brew winners" (PLAN.md §14 #158): per catalogue kind, the top
/// option by wins — "won 7 of 12" — gated at **min 3 tried** (same
/// statistical-gate spirit as #28's other findings) so a single lucky brew
/// doesn't read as a verdict. Hidden entirely when no kind clears the gate.
/// Styled like `DataQualityCard` (#89: no card background, 17pt/800 title,
/// neutral700 supporting text, 44pt rows) rather than `BriefCard`'s boxed
/// treatment, since this is the same "tap a row to filter" shape.
struct BrewWinnersCard: View {
    struct Winner: Identifiable {
        let kind: BrewKind
        let option: BrewOption
        let tried: Int
        let won: Int
        var id: Int { option.id }
    }

    let winners: [Winner]
    var onSelect: ((FilterDimension, FacetKey) -> Void)?

    var body: some View {
        if !winners.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Brew winners")
                    .font(.system(size: 17, weight: Theme.Weight.heavy))
                ForEach(winners) { winner in
                    row(winner)
                }
            }
        }
    }

    private func row(_ winner: Winner) -> some View {
        let content = HStack {
            Text(winner.kind.displayName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            Text(winner.option.label)
                .font(.system(size: 12, weight: Theme.Weight.semibold))
                .foregroundStyle(Theme.Colors.text)
            Text("won \(winner.won) of \(winner.tried)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.neutral700)
        }
        .frame(minHeight: Theme.minHitTarget)

        return Group {
            if let onSelect {
                Button {
                    onSelect(winner.kind.filterDimension, .vocabID(winner.option.id))
                } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
}

extension BrewWinnersCard.Winner {
    /// Builds the gated per-kind winner list from `CoffeeIndex.brewWinRates`
    /// — recipe → device → grind → temp (Radu's sentence order), each kind's
    /// top-by-wins entry only, and only once it has **≥ 3 tried**.
    static func build(index: CoffeeIndex) -> [BrewWinnersCard.Winner] {
        [BrewKind.recipe, .device, .grind, .temp].compactMap { kind in
            guard let top = index.brewWinRates(kind: kind).first, top.tried >= 3, top.won > 0 else { return nil }
            return BrewWinnersCard.Winner(kind: kind, option: top.option, tried: top.tried, won: top.won)
        }
    }
}
