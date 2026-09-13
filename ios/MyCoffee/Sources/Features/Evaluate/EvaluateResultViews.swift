import SwiftUI

/// The resolved-fields line at the top of the evaluate result (#125): roaster,
/// origin(s), process, roaster country — same "missing fields omit their row
/// entirely" rule as the rest of the app (PLAN.md §6.3), so an unresolved
/// field just isn't there rather than printing "Unknown". The whole row is
/// omitted when nothing resolved at all.
struct EvaluateFactsRow: View {
    let fields: EvaluateFields
    let vocabulary: Vocabulary

    private var roasterName: String? { fields.roasterId.flatMap { vocabulary.roasters[$0]?.name } }
    private var roasterCountryName: String? { fields.roasterCountryId.flatMap { vocabulary.countries[$0]?.name } }
    private var originCountries: [Country] { fields.originCountryIds.compactMap { vocabulary.countries[$0] } }

    private var hasAnyFact: Bool {
        roasterName != nil || !originCountries.isEmpty || fields.profile != nil || roasterCountryName != nil
    }

    var body: some View {
        if hasAnyFact {
            VStack(alignment: .leading, spacing: 6) {
                if let roasterName {
                    factLine(title: roasterName, subtitle: roasterCountryName)
                }
                if !originCountries.isEmpty {
                    HStack(spacing: 6) {
                        FlagsView(isoCodes: originCountries.map(\.isoCode))
                        Text(originCountries.map(\.name).joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.text)
                    }
                }
                if let profile = fields.profile {
                    Text(profile.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
            }
        }
    }

    private func factLine(title: String, subtitle: String?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: Theme.Weight.semibold))
                .foregroundStyle(Theme.Colors.text)
            if let subtitle {
                Text("· \(subtitle)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
        }
    }
}

/// The headline "fit" number, gated behind `EvaluateCoffeeView.showHeadline`
/// (#163) — flipping that one constant is the whole ship decision. The
/// low-confidence badge is independent of the flag: it was never gated
/// (#106), and it's exactly the context that matters most while the number
/// stays hidden.
struct EvaluateHeadlineBlock: View {
    let evaluation: Evaluation

    private var isLowConfidence: Bool { evaluation.confidence == .low }
    private var showsNumber: Bool {
        EvaluateCoffeeView.showHeadline && !isLowConfidence && evaluation.score != nil
    }

    var body: some View {
        Group {
            if showsNumber, let score = evaluation.score {
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 56, weight: Theme.Weight.heavy))
                        .foregroundStyle(Theme.Colors.accent)
                    // #106: never "predicted rating" — this is a description
                    // of overlap with what Radu already buys, not a forecast.
                    Text("matches what you buy")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
                .frame(maxWidth: .infinity)
            } else if isLowConfidence {
                lowConfidenceBadge
            }
        }
    }

    private var lowConfidenceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: Symbols.needsReview)
                .font(.system(size: 12))
            Text("Low confidence — roaster, origin and process are all new to you")
                .font(.system(size: 12, weight: Theme.Weight.semibold))
        }
        .foregroundStyle(Theme.Colors.neutral700)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.Colors.neutral100))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Affinity / value / novelty, **equal visual weight** (#106/#125's own
/// spec) — the headline number is the hook, these three are what's
/// defensible, so none of the three outranks the others visually.
struct EvaluateComponentsRow: View {
    let components: EvaluationComponents

    var body: some View {
        VStack(spacing: 12) {
            componentCard(
                icon: Symbols.evaluateAffinity,
                title: "Affinity",
                caption: "matches your usual"
            ) {
                Text("\(components.affinity.score)")
                    .font(.system(size: 22, weight: Theme.Weight.heavy))
                    .foregroundStyle(Theme.Colors.text)
            }

            componentCard(
                icon: Symbols.eurosign,
                title: "Value",
                caption: valueCaption
            ) {
                if let value = components.value {
                    valueMeter(pillCount: value.pillCount, band: ValueRating.Band(rawValue: value.band))
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: Theme.Weight.heavy))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
            }

            componentCard(
                icon: Symbols.evaluateNovelty,
                title: "Novelty",
                caption: noveltyCaption
            ) {
                EmptyView()
            }
        }
    }

    private var valueCaption: String {
        guard let value = components.value, let band = ValueRating.Band(rawValue: value.band) else {
            return "Not enough similarly-priced coffees yet to judge"
        }
        return band.label.capitalized
    }

    private var noveltyCaption: String {
        switch (components.novelty.isNewRoaster, components.novelty.isNewOrigin) {
        case (true, true): return "New roaster · new origin"
        case (true, false): return "New roaster"
        case (false, true): return "New origin"
        case (false, false): return "Roaster and origin you already know"
        }
    }

    @ViewBuilder
    private func componentCard<Trailing: View>(
        icon: String, title: String, caption: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.text)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Colors.neutral100))
    }

    /// Same five-pill meter shape as `CoffeeRowView.valueMeter` — kept as its
    /// own small copy here rather than importing a private view; #181's
    /// planned `ValueMeterView` extraction will fold this in along with the
    /// other two.
    private func valueMeter(pillCount: Int, band: ValueRating.Band?) -> some View {
        let tone = bandColor(band)
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: Theme.Radius.pill)
                    .fill(pip < pillCount ? tone : tone.opacity(0.15))
                    .frame(width: 8, height: 4)
            }
        }
    }

    private func bandColor(_ band: ValueRating.Band?) -> Color {
        switch band {
        case .overpaid: return Theme.Colors.valueOverpaid
        case .poor: return Theme.Colors.valuePoor
        case .fair: return Theme.Colors.valueFair
        case .good: return Theme.Colors.valueGood
        case .great: return Theme.Colors.valueGreat
        case nil: return Theme.Colors.neutral700
        }
    }
}

/// Surfaces the two price-plumbing gaps the row calls out by name: no price
/// recognised at all in the pasted text, versus a price that was recognised
/// but has too few peers in its band to judge value against — two different
/// problems needing two different explanations, both fixable by going back
/// to the text step.
struct EvaluatePriceBanner: View {
    let text: String
    let onEditText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: Symbols.needsReview)
                    .font(.system(size: 12))
                Text(text)
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.Colors.neutral700)
            Button("Edit the pasted text", action: onEditText)
                .font(.system(size: 12, weight: Theme.Weight.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Colors.neutral100))
    }

    /// `nil` when the value component scored cleanly — no banner needed.
    static func message(for fields: EvaluateFields, components: EvaluationComponents) -> String? {
        guard components.value == nil else { return nil }
        if fields.pricePer100gEur == nil {
            return "No price found in your text — the value half of the score needs one (e.g. \"35 RON / 250g\")."
        }
        return "Not enough similarly-priced coffees yet to judge value against — the affinity and novelty components still count."
    }
}
