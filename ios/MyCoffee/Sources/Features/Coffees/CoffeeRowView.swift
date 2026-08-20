import SwiftUI

/// The Vivino-style listing row (PLAN.md §6.1): 84×84 thumb · roaster flag +
/// name · farm/lot title (2 lines, semibold) · origin flag + "Farm, Country"
/// · `ProcessTag` + rating + heart · right-aligned price / price-per-100g ·
/// full-width grey footer strip with the date (or month-year when not sorted
/// by date, so the brief's required date is never lost).
struct CoffeeRowView: View {
    let coffee: Coffee
    let vocabulary: Vocabulary
    let sort: SortOption

    @EnvironmentObject private var store: CoffeeStore
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 84

    private var roaster: Roaster? { coffee.roaster(vocabulary: vocabulary) }
    private var roasterCountry: Country? { coffee.roasterCountry(vocabulary: vocabulary) }
    private var originCountry: Country? { coffee.primaryOriginCountry(vocabulary: vocabulary) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Thumbnail(urlString: coffee.images?.thumb, size: thumbSize, rotationQuarterTurns: coffee.rotationTurns)

                VStack(alignment: .leading, spacing: 4) {
                    if let roaster {
                        HStack(spacing: 4) {
                            FlagView(isoCode: roasterCountry?.isoCode)
                            Text(roaster.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(coffee.displayTitle(vocabulary: vocabulary))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if let subtitle = coffee.originSubtitle(vocabulary: vocabulary) {
                        HStack(spacing: 4) {
                            FlagView(isoCode: coffee.isBlend ? nil : originCountry?.isoCode)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // The tag cluster WRAPS. Each pill keeps its intrinsic width
                    // (so the earlier icon-only collapse can't come back), but a
                    // coffee with two tags — process + Decaf — plus the rating
                    // would otherwise force this row wider than the screen and
                    // shove the whole row (thumbnail included) off both edges.
                    // WrapLayout drops the overflow onto a second line instead.
                    HStack(alignment: .top, spacing: 8) {
                        WrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ProcessTag(profile: coffee.profile)
                            if coffee.isDecaf {
                                DecafBadge()
                            }
                            if let rating = coffee.rating {
                                HStack(spacing: 3) {
                                    Image(systemName: Symbols.starFill)
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        // A `Button` nested inside the row's `NavigationLink`
                        // label: SwiftUI hit-tests it first, so the heart tap
                        // never falls through to the row's own navigation.
                        Button {
                            store.toggleFavorite(coffee)
                        } label: {
                            Image(systemName: coffee.isFavorite ? Symbols.heartFill : Symbols.heart)
                                .foregroundStyle(coffee.isFavorite ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    if let priceLabel = coffee.priceLabel {
                        Text(priceLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                    if let ppgLabel = coffee.pricePer100gLabel {
                        Text(ppgLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)

            Text(sort == .dateBought ? PlainDateFormatting.exact(coffee.purchasedOn) : SortOption.monthYearLabel(for: coffee))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .padding(.top, 8)
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
