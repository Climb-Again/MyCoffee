import SwiftUI
import UIKit

/// The coffee detail page (PLAN.md §6.3): full-bleed photo with real
/// `ToolbarItem` back/share (never `.navigationBarBackButtonHidden` +
/// overlay, which kills edge-swipe-back), a white card curving up over it,
/// an inset thumbnail, roaster row, title, pill row, process, fact rows,
/// note blocks, then rating-ordered rails.
struct CoffeeDetailView: View {
    private let initialCoffee: Coffee
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    init(coffee: Coffee) {
        self.initialCoffee = coffee
    }

    /// The compact snapshot doesn't carry notes/images (PLAN.md §4) — reads
    /// through `store.index` so the `.task` below's `loadDetail` merge shows
    /// up here without every call site needing to re-fetch by hand.
    private var coffee: Coffee { store.index.coffee(id: initialCoffee.id) ?? initialCoffee }

    private var vocabulary: Vocabulary { store.index.vocabulary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImage
                card
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            await store.loadDetail(for: initialCoffee)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: Symbols.chevronBackward)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: coffee.displayTitle(vocabulary: vocabulary)) {
                    Image(systemName: Symbols.share)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
    }

    // MARK: - Hero

    private var heroImage: some View {
        ZStack {
            if let url = (coffee.images?.display).flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(height: 320)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var heroPlaceholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: Symbols.emptyCup)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            ratingHeader
            inlineThumbnail
            roasterRow
            titleBlock
            pillRow
            processBlock
            if !factRows.isEmpty {
                FactRowsCard(rows: factRows)
            }
            notesSection
            railsSection
        }
        .padding(20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .offset(y: -28)
    }

    private var ratingHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            if let rating = coffee.rating {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    starRow(for: rating)
                }
            } else {
                Text("Unrated")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if coffee.hasOpenReview {
                Label("Needs review", systemImage: Symbols.needsReview)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func starRow(for rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: Double(index) < rating ? Symbols.starFill : Symbols.star)
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private var inlineThumbnail: some View {
        Thumbnail(urlString: coffee.images?.thumb, size: 64, cornerRadius: 12)
            .offset(y: -48)
            .padding(.bottom, -48)
    }

    private var roasterRow: some View {
        let roaster = coffee.roaster(vocabulary: vocabulary)
        let roasterCountry = coffee.roasterCountry(vocabulary: vocabulary)

        return Group {
            if let roaster {
                HStack {
                    // Pushback #7: the flag beside the roaster is a *country*
                    // flag, so it opens the roaster's country page; the name
                    // opens the roaster page. Two separate tap targets, not one.
                    if FeatureFlags.tapNavigatesToEntityPages, let roasterCountry {
                        NavigationLink {
                            CountryPageView(countryID: roasterCountry.id, role: .roaster)
                        } label: {
                            FlagView(isoCode: roasterCountry.isoCode)
                        }
                        .buttonStyle(.plain)
                    } else {
                        FlagView(isoCode: roasterCountry?.isoCode)
                    }

                    if FeatureFlags.tapNavigatesToEntityPages {
                        NavigationLink {
                            RoasterPageView(roasterID: roaster.id)
                        } label: {
                            Text(roaster.name)
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(roaster.name)
                            .font(.subheadline.weight(.medium))
                    }

                    Spacer()
                    if FeatureFlags.tapNavigatesToEntityPages {
                        Image(systemName: Symbols.chevronRight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var titleBlock: some View {
        Text(coffee.displayTitle(vocabulary: vocabulary))
            .font(.title2.weight(.bold))
    }

    private var pillRow: some View {
        WrapLayout() {
            if coffee.isBlend {
                InfoPill(icon: nil, text: "🏳️ Blend")
            } else if let country = coffee.primaryOriginCountry(vocabulary: vocabulary) {
                // Pushback #7: the origin flag (folded into this pill's text)
                // opens the origin-country page.
                if FeatureFlags.tapNavigatesToEntityPages {
                    NavigationLink {
                        CountryPageView(countryID: country.id, role: .origin)
                    } label: {
                        InfoPill(icon: nil, text: (country.isoCode.flagEmoji ?? "🏳️") + " " + country.name)
                    }
                    .buttonStyle(.plain)
                } else {
                    InfoPill(icon: nil, text: (country.isoCode.flagEmoji ?? "🏳️") + " " + country.name)
                }
            }
            if let altitude = coffee.altitudeLabel {
                InfoPill(icon: Symbols.mountain, text: altitude)
            }
            if let weight = coffee.weightLabel {
                InfoPill(icon: Symbols.scale, text: weight)
            }
        }
    }

    private var processBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProcessTag(profile: coffee.profile)
                if coffee.isDecaf {
                    DecafBadge()
                }
            }
            if let detail = coffee.profileDetail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var factRows: [FactRow] {
        var rows: [FactRow] = []
        rows.append(FactRow(symbol: Symbols.calendar, label: "Purchased", value: PlainDateFormatting.exact(coffee.purchasedOn)))
        if let roastedOn = coffee.roastedOn {
            rows.append(FactRow(symbol: Symbols.calendar, label: "Roasted", value: PlainDateFormatting.exact(roastedOn)))
        }
        if let priceLabel = coffee.priceLabel {
            if let originalAmount = coffee.priceOriginalAmount, let currency = coffee.priceOriginalCurrency, currency != "EUR" {
                rows.append(FactRow(symbol: Symbols.eurosign, label: "Price", value: "\(priceLabel) (\(originalAmount.formatted()) \(currency))"))
            } else {
                rows.append(FactRow(symbol: Symbols.eurosign, label: "Price", value: priceLabel))
            }
        }
        if let ppgLabel = coffee.pricePer100gLabel {
            rows.append(FactRow(symbol: Symbols.eurosign, label: "Price / 100 g", value: ppgLabel))
        }
        return rows
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let note = coffee.farmLotNote, !note.isEmpty {
                NoteBlock(title: "Farm & lot", text: note)
            }
            if let note = coffee.brewGuideNote, !note.isEmpty {
                NoteBlock(title: "Brew guide", text: note)
            }
            if let note = coffee.roasterCopyNote, !note.isEmpty {
                DisclosureGroup("From the roaster") {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Rails

    private var railsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(rails) { rail in
                RailView(rail: rail, vocabulary: vocabulary)
            }
        }
    }

    private var rails: [CoffeeRail] {
        var result: [CoffeeRail] = []
        let index = store.index

        if let roaster = coffee.roaster(vocabulary: vocabulary) {
            var filter = CoffeeFilter()
            filter.roasterIDs = [coffee.roasterId]
            let matching = index.coffees(matching: filter, sortedBy: .rating).filter { $0.id != coffee.id }
            if matching.count >= 2 {
                result.append(CoffeeRail(
                    id: "roaster", title: "More from \(roaster.name)", coffees: matching,
                    moreFilter: filter, moreDestination: .roaster(id: roaster.id)
                ))
            }
        }

        if !coffee.isBlend, let country = coffee.primaryOriginCountry(vocabulary: vocabulary) {
            var filter = CoffeeFilter()
            filter.originCountryIDs = [country.id]
            let matching = index.coffees(matching: filter, sortedBy: .rating).filter { $0.id != coffee.id }
            if matching.count >= 2 {
                result.append(CoffeeRail(
                    id: "origin", title: "More from \(country.name)", coffees: matching,
                    moreFilter: filter, moreDestination: .country(id: country.id, role: .origin)
                ))
            }
        }

        if let profile = coffee.profile {
            var filter = CoffeeFilter()
            filter.profiles = [profile]
            let matching = index.coffees(matching: filter, sortedBy: .rating).filter { $0.id != coffee.id }
            if matching.count >= 2 {
                result.append(CoffeeRail(
                    id: "profile", title: "More \(profile.displayName.lowercased())", coffees: matching,
                    moreFilter: filter, moreDestination: .filteredList
                ))
            }
        }

        return result
    }
}

private struct InfoPill: View {
    let icon: String?
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

private struct NoteBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
