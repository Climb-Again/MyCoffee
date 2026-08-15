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
    @ObservedObject private var reviewCache = ReviewFeedCache.shared
    @State private var showReview = false
    @State private var showEdit = false
    @State private var fullTextExpanded = true
    @State private var showFullPhoto = false

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
        .task {
            await reviewCache.ensureLoaded()
        }
        .toolbar {
            // Only the trailing Share/Edit buttons are custom — the system back
            // button stays (one arrow, and it keeps edge-swipe-back working). A
            // second custom back button here is what produced the duplicate arrow.
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: coffee.displayTitle(vocabulary: vocabulary)) {
                    Image(systemName: Symbols.share)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: Symbols.edit)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .sheet(isPresented: $showReview) {
            CoffeeReviewSheet(coffeeId: coffee.id) {
                Task {
                    await reviewCache.refresh()
                    await store.loadDetail(for: initialCoffee)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullPhoto) {
            ZoomableImageView(urlString: coffee.images?.display)
        }
        .sheet(isPresented: $showEdit) {
            CoffeeEditSheet(coffee: coffee)
        }
    }

    private var hasPhoto: Bool {
        (coffee.images?.display).flatMap(URL.init(string:)) != nil
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
        // Tap the (cropped) hero to see the whole photo full-screen.
        .contentShape(Rectangle())
        .onTapGesture {
            if hasPhoto { showFullPhoto = true }
        }
        .overlay(alignment: .bottomTrailing) {
            if hasPhoto {
                Image(systemName: Symbols.reviewZoom)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
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
            roasterRow
            titleBlock
            pillRow
            processBlock
            if !factRows.isEmpty {
                FactRowsCard(rows: factRows)
            }
            notesSection
            fullTextSection
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
            if coffee.hasOpenReview && reviewCache.hasReviewableTasks(for: coffee.id) {
                // Tappable: the marker isn't just a status, it launches the
                // review for this coffee's open fields (PLAN.md §6.5).
                // Gated on the real feed, not just the coarse `reviewState`
                // column, so a coffee whose only open item is a non-client-
                // reviewable field (e.g. a `desc_*` prose split) never shows
                // an affordance that opens to an empty "All set" sheet
                // (PLAN.md §11 #37).
                Button {
                    showReview = true
                } label: {
                    Label("Review", systemImage: Symbols.needsReview)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
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
        let origins = coffee.allOriginCountries(vocabulary: vocabulary)
        return WrapLayout() {
            // A blend gets a "Blend" marker plus one pill per origin country; a
            // single-origin coffee just gets its one country pill. Either way,
            // every country pill is its own tap target into the origin page.
            if coffee.isBlend {
                InfoPill(icon: nil, text: "🏳️ Blend")
            }
            if !origins.isEmpty {
                ForEach(origins) { country in
                    originPill(for: country)
                }
            } else if coffee.isBlend == false, let country = coffee.primaryOriginCountry(vocabulary: vocabulary) {
                originPill(for: country)
            }
            if let altitude = coffee.altitudeLabel {
                InfoPill(icon: Symbols.mountain, text: altitude)
            }
            if let weight = coffee.weightLabel {
                InfoPill(icon: Symbols.scale, text: weight)
            }
        }
    }

    @ViewBuilder
    private func originPill(for country: Country) -> some View {
        let text = (country.isoCode.flatMap { $0.flagEmoji } ?? "🏳️") + " " + country.name
        // Pushback #7: the origin flag (folded into this pill's text) opens the
        // origin-country page.
        if FeatureFlags.tapNavigatesToEntityPages {
            NavigationLink {
                CountryPageView(countryID: country.id, role: .origin)
            } label: {
                InfoPill(icon: nil, text: text)
            }
            .buttonStyle(.plain)
        } else {
            InfoPill(icon: nil, text: text)
        }
    }

    private var processBlock: some View {
        // Full processing name (e.g. "Cold Natural") shown in brackets next to
        // the coarse profile label ("Natural"). Skipped when the full name adds
        // nothing — i.e. it's identical to the label (case-insensitive).
        let detail = coffee.profileDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = coffee.profile?.displayName ?? ""
        let fullName: String? = {
            guard let detail, !detail.isEmpty,
                  detail.caseInsensitiveCompare(label) != .orderedSame else { return nil }
            return detail
        }()

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            ProcessTag(profile: coffee.profile)
            if let fullName {
                Text("(\(fullName))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if coffee.isDecaf {
                DecafBadge()
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

    /// The raw scraped text (title / caption / description) exactly as ingested.
    /// The curated `desc_*` note blocks above are empty on the freshly-extracted
    /// "probe" coffees — this section is what actually shows their full content.
    /// Selectable so a lot number or link can be copied straight out.
    private var fullTextSection: some View {
        let blocks: [(label: String, text: String)] = [
            ("Title", coffee.rawTitle),
            ("Caption", coffee.rawCaption),
            ("Description", coffee.rawDescription)
        ].compactMap { label, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (label, value)
        }

        return Group {
            if !blocks.isEmpty {
                // Expanded by default (this is the coffee's full content), but
                // collapsible so a very long caption doesn't wall off the rails.
                DisclosureGroup(isExpanded: $fullTextExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(blocks, id: \.label) { block in
                            VStack(alignment: .leading, spacing: 4) {
                                // Only tag each block when more than one is present,
                                // so a lone caption reads as plain body text.
                                if blocks.count > 1 {
                                    Text(block.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(block.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("Full text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
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
            filter.roasterIDs = [roaster.id]
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

