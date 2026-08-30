import SwiftUI

/// The 2a-redesign listing row (`#85`, `design/coffees_redesign/README.md`
/// §Row): 88×88 photo with a pinned favourite circle · roaster/title/origin/
/// process middle column · a right-aligned rating + price + value-meter
/// column. Altitude, weight, the process capsule, origin country-code boxes,
/// the star glyph and the grey date strip are all deliberately gone — the
/// purchase date now lives in the month header (`CoffeesListView`).
struct CoffeeRowView: View {
    let coffee: Coffee
    let vocabulary: Vocabulary

    @EnvironmentObject private var store: CoffeeStore
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 88

    private var roaster: Roaster? { coffee.roaster(vocabulary: vocabulary) }

    /// "In the user's highest-average set with at least ~5 rated bags"
    /// (design handoff §State) — membership in `CoffeeIndex.topRoasterIDs()`,
    /// not just the single best roaster (that distinction is the detail
    /// page's "your best roaster", `#88`).
    private var isTopRoaster: Bool {
        guard let roasterId = coffee.roasterId else { return false }
        return store.index.topRoasterIDs().contains { $0.id == roasterId }
    }

    /// The user's average for this coffee's origin country — shown on **every**
    /// row, not just top origins (`UPDATE_BRIEF.md` §C). The old version only
    /// appended an average when the origin cleared the top-origin bar, and
    /// coloured the line blue when it did, so the feed alternated between blue
    /// lines with a number and grey lines without one and read as arbitrary.
    ///
    /// `nil` — name alone — in exactly two cases: fewer than `minRatedForAverage`
    /// rated bags from that country, where an average would be noise; and blends,
    /// where `originSubtitle` lists several countries and a single trailing
    /// number could not say which one it belonged to.
    private var originAverage: Double? {
        let origins = coffee.allOriginCountries(vocabulary: vocabulary)
        guard origins.count == 1, let country = origins.first else { return nil }
        return store.index.topOriginCountryIDs(minCount: Self.minRatedForAverage)
            .first { $0.id == country.id }?.average
    }

    /// Below this many rated bags from a country, its average is noise — show
    /// the country name alone (`UPDATE_BRIEF.md` §C: "< ~3").
    private static let minRatedForAverage = 3

    private var originLine: String? {
        guard let base = coffee.originSubtitle(vocabulary: vocabulary) else { return nil }
        guard let originAverage else { return base }
        return "\(base) · \(String(format: "%.1f", originAverage))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            photo
            middleColumn
            Spacer(minLength: 0)
            rightColumn
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Photo + favourite

    private var photo: some View {
        Thumbnail(
            urlString: coffee.images?.thumb,
            size: thumbSize,
            cornerRadius: Theme.Radius.photo,
            rotationQuarterTurns: coffee.rotationTurns
        )
        .overlay(alignment: .bottomTrailing) {
            favoriteButton.offset(x: 8, y: 8)
        }
    }

    /// A `Button` nested inside the row's `NavigationLink` label: SwiftUI
    /// hit-tests it first, so the heart tap never falls through to the row's
    /// own navigation. 44×44 transparent hit area around a 28pt visible
    /// circle, per the handoff's minimum-hit-target rule.
    private var favoriteButton: some View {
        Button {
            store.toggleFavorite(coffee)
        } label: {
            ZStack {
                Circle().fill(coffee.isFavorite ? Theme.Colors.accent : Theme.Colors.surface)
                if !coffee.isFavorite {
                    Circle().strokeBorder(Theme.Colors.neutral300, lineWidth: 1)
                }
                Image(systemName: coffee.isFavorite ? Symbols.heartFill : Symbols.heart)
                    .font(.system(size: 13))
                    .foregroundStyle(coffee.isFavorite ? Theme.Colors.onAccent : Theme.Colors.neutral700)
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Middle column

    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let roaster {
                Text(roaster.name)
                    .textCase(.uppercase)
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(0.6)
                    .foregroundStyle(isTopRoaster ? Theme.Colors.accent : Theme.Colors.neutral700)
                    .lineLimit(1)
            }

            Text(coffee.displayTitle(vocabulary: vocabulary))
                .font(.system(size: 17, weight: Theme.Weight.heavy))
                .tracking(-0.34)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)

            if let originLine {
                HStack(spacing: 4) {
                    // One flag per origin: a blend used to force `nil` here and
                    // render a lone white flag beside text that already listed
                    // every country. `allOriginCountries` returns the single
                    // country for a single-origin coffee, so this is unchanged
                    // for the other 395 of 411.
                    FlagsView(isoCodes: coffee.allOriginCountries(vocabulary: vocabulary).map(\.isoCode))
                        .font(.system(size: 13))
                    Text(originLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
            }

            // #104: the tinted oval is back. The 2a handoff §Row called for
            // "11pt plain text, no tinted capsule"; Radu wants the capsule.
            // `ProcessTag` was never deleted — it still carries its own
            // light/dark hex pair per process (so it needs none of #100's
            // treatment) and the two layout guards paid for earlier: an
            // explicit HStack rather than a `Label`, which collapsed to
            // icon-only under `fixedSize`, plus lineLimit(1) + fixedSize
            // against the character-per-line wrap.
            //
            // Still gated on a non-nil profile: an unknown process omits the
            // row entirely rather than showing ProcessTag's "Unknown" pill,
            // per "missing fields omit their row".
            if coffee.profile != nil {
                ProcessTag(profile: coffee.profile)
            }
        }
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let rating = coffee.rating {
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 26, weight: Theme.Weight.heavy))
                    .foregroundStyle(rating >= 4.5 ? Theme.Colors.accent : Theme.Colors.text)
            }
            if let priceLabel = coffee.priceLabel {
                Text(priceLabel)
                    .font(.system(size: 13, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.text)
            }
            if let pricePer100gEur = coffee.pricePer100gEur {
                Text(pricePer100gEur.formatted(.currency(code: "EUR")) + "/100g")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            if let valueRating = store.index.valueBand(for: coffee) {
                valueMeter(valueRating)
                    .padding(.top, 2)
                if let band = valueRating.band {
                    Text(verdictLabel(band))
                        .font(.system(size: 10, weight: Theme.Weight.semibold))
                        .tracking(0.8)
                        .foregroundStyle(band.isPositive ? Theme.Colors.accent : Theme.Colors.neutral700)
                }
            }
        }
        .frame(width: 96, alignment: .trailing)
    }

    private func valueMeter(_ rating: ValueRating) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: Theme.Radius.pill)
                    .fill(
                        pip < rating.pillCount
                            ? ((rating.band?.isPositive ?? false) ? Theme.Colors.accent : Theme.Colors.neutral700)
                            : Theme.Colors.neutral300
                    )
                    .frame(width: 8, height: 4)
            }
        }
    }

    /// One word per pill (#105) — the label and the meter are the same five-step
    /// scale, so they cannot disagree the way 4-pills-FAIR and 2-pills-FAIR did.
    /// `.overpaid` also replaces the old `.pricey` (`UPDATE_BRIEF.md` §B): the
    /// point is that you rated it low for what it cost, not that it was dear.
    private func verdictLabel(_ band: ValueRating.Band) -> String {
        switch band {
        case .great: return "GREAT VALUE"
        case .good: return "GOOD VALUE"
        case .fair: return "FAIR VALUE"
        case .poor: return "POOR VALUE"
        case .overpaid: return "OVERPAID"
        }
    }
}

enum PlainDateFormatting {
    static func exact(_ date: PlainDate) -> String {
        Self.formatter.string(from: date.utcMidnight)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.utc
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
