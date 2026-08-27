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
    private var originCountry: Country? { coffee.primaryOriginCountry(vocabulary: vocabulary) }

    /// "In the user's highest-average set with at least ~5 rated bags"
    /// (design handoff §State) — membership in `CoffeeIndex.topRoasterIDs()`,
    /// not just the single best roaster (that distinction is the detail
    /// page's "your best roaster", `#88`).
    private var isTopRoaster: Bool {
        guard let roasterId = coffee.roasterId else { return false }
        return store.index.topRoasterIDs().contains { $0.id == roasterId }
    }

    /// The best matching average among this coffee's origin countries that
    /// clears the top-origin bar — `nil` when none do, so the origin line
    /// stays plain. `topOriginCountryIDs()` is sorted descending by average,
    /// so the first match is the highest one this coffee can claim.
    private var topOriginAverage: Double? {
        let topOrigins = store.index.topOriginCountryIDs()
        guard !topOrigins.isEmpty else { return nil }
        let countryIDs = Set(coffee.allOriginCountries(vocabulary: vocabulary).map(\.id))
        return topOrigins.first { countryIDs.contains($0.id) }?.average
    }

    private var originLine: String? {
        guard let base = coffee.originSubtitle(vocabulary: vocabulary) else { return nil }
        guard let topOriginAverage else { return base }
        return "\(base) · \(String(format: "%.1f", topOriginAverage))"
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
                Circle().fill(coffee.isFavorite ? Theme.Colors.accent : Color.white)
                if !coffee.isFavorite {
                    Circle().strokeBorder(Theme.Colors.neutral300, lineWidth: 1)
                }
                Image(systemName: coffee.isFavorite ? Symbols.heartFill : Symbols.heart)
                    .font(.system(size: 13))
                    .foregroundStyle(coffee.isFavorite ? Color.white : Theme.Colors.neutral700)
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
                    FlagView(isoCode: coffee.isBlend ? nil : originCountry?.isoCode)
                        .font(.system(size: 13))
                    Text(originLine)
                        .font(.system(size: 12))
                        .foregroundStyle(topOriginAverage != nil ? Theme.Colors.accent700 : Theme.Colors.neutral700)
                }
            }

            if let profile = coffee.profile {
                Text(profile.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
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
                Text(verdictLabel(valueRating.band))
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(0.8)
                    .foregroundStyle(valueRating.band == .great ? Theme.Colors.accent : Theme.Colors.neutral700)
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
                            ? (rating.band == .great ? Theme.Colors.accent : Theme.Colors.neutral700)
                            : Theme.Colors.neutral300
                    )
                    .frame(width: 8, height: 4)
            }
        }
    }

    private func verdictLabel(_ band: ValueRating.Band) -> String {
        switch band {
        case .great: return "GREAT VALUE"
        case .fair: return "FAIR VALUE"
        case .pricey: return "PRICEY"
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
