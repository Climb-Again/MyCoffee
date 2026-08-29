import SwiftUI
import UIKit

/// The coffee detail page — 2a redesign (`#88`,
/// `design/coffees_redesign/README.md` §Screen 2, folds in `#82`): a 300pt
/// full-bleed hero with real `ToolbarItem` back (never
/// `.navigationBarBackButtonHidden` + a custom overlay, which killed
/// edge-swipe-back and duplicated the arrow the one time this was tried —
/// see the toolbar below) plus floating favourite/share/edit circles, a
/// white card overlapping it by 20pt, rating header, roaster row, title,
/// pill row, a price block with the value meter, fact rows, a flavour-
/// profile section, note blocks, then rating-ordered rails.
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
            // Only the trailing buttons are custom — the system back button
            // stays (one arrow, and it keeps edge-swipe-back working). A
            // second custom back button here is what produced the duplicate
            // arrow the one time this was tried, so the handoff's leading
            // "back circle" isn't reproduced pixel-for-pixel; the system
            // chevron plays that role instead over the transparent bar.
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: coffee.displayTitle(vocabulary: vocabulary)) {
                    Image(systemName: Symbols.share)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.92), in: Circle())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: Symbols.edit)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.92), in: Circle())
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
            ZoomableImageView(
                urlString: coffee.images?.display,
                initialRotationQuarterTurns: coffee.rotationTurns,
                onRotate: { turns in
                    Task { await store.setRotation(coffeeId: coffee.id, quarterTurns: turns) }
                }
            )
        }
        .sheet(isPresented: $showEdit) {
            CoffeeEditSheet(coffee: coffee)
        }
    }

    private var hasPhoto: Bool {
        (coffee.images?.display).flatMap(URL.init(string:)) != nil
    }

    /// Design handoff §Screen 2: `#0078ff` fill, white heart, 44×44.
    private var favoriteButton: some View {
        Button {
            store.toggleFavorite(coffee)
        } label: {
            Image(systemName: coffee.isFavorite ? Symbols.heartFill : Symbols.heart)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.accent, in: Circle())
        }
    }

    // MARK: - Hero

    private var heroImage: some View {
        ZStack {
            if let url = (coffee.images?.display).flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                            .rotationEffect(.degrees(Double(coffee.rotationTurns) * 90))
                    } else {
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(height: 300)
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
                    .foregroundStyle(Theme.Colors.onAccent)
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
            priceBlock
            if !factRows.isEmpty {
                FactRowsList(rows: factRows)
            }
            notesSection
            fullTextSection
            railsSection
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.Radius.card, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: Theme.Radius.card,
                style: .continuous
            )
            .fill(Theme.Colors.surface)
        )
        .offset(y: -20)
    }

    private var ratingHeader: some View {
        HStack(alignment: .center) {
            if let rating = coffee.rating {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 40, weight: Theme.Weight.heavy))
                        .tracking(-1.2)
                        .foregroundStyle(Theme.Colors.accent)
                    starRow(for: rating)
                }
            } else {
                Text("Unrated")
                    .font(.system(size: 22, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            Spacer()
            if coffee.hasOpenReview && reviewCache.hasReviewableTasks(for: coffee.id) {
                // Tappable: the pill isn't just a status, it launches the
                // review for this coffee's open fields (PLAN.md §6.5).
                // Gated on the real feed, not just the coarse `reviewState`
                // column, so a coffee whose only open item is a non-client-
                // reviewable field (e.g. a `desc_*` prose split) never shows
                // an affordance that opens to an empty "All set" sheet
                // (PLAN.md §11 #37).
                Button {
                    showReview = true
                } label: {
                    Text(reviewPillText)
                        .font(.system(size: 11, weight: Theme.Weight.semibold))
                        .foregroundStyle(Theme.Colors.accent700)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Theme.minHitTarget)
                        .background(Theme.Colors.accent100, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The feed's item count for this coffee, one row per (coffeeId, field) —
    /// "2 fields to review" per the design handoff. Falls back to a plain
    /// label if the count somehow reads 0 while the gate above is still true
    /// (a feed refresh mid-flight), rather than showing "0 fields to review".
    private var reviewPillText: String {
        let count = reviewCache.reviewableFieldCount(for: coffee.id)
        guard count > 0 else { return "Needs review" }
        return "\(count) field\(count == 1 ? "" : "s") to review"
    }

    private func starRow(for rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: Double(index) < rating ? Symbols.starFill : Symbols.star)
                    .foregroundStyle(Double(index) < rating ? Theme.Colors.accent : Theme.Colors.neutral300)
                    .font(.system(size: 13))
            }
        }
    }

    private var roasterRow: some View {
        let roaster = coffee.roaster(vocabulary: vocabulary)
        let roasterCountry = coffee.roasterCountry(vocabulary: vocabulary)

        return Group {
            if let roaster {
                HStack(spacing: 6) {
                    // Pushback #7: the flag beside the roaster is a *country*
                    // flag, so it opens the roaster's country page; the name
                    // opens the roaster page. Two separate tap targets, not one.
                    if FeatureFlags.tapNavigatesToEntityPages, let roasterCountry {
                        NavigationLink {
                            CountryPageView(countryID: roasterCountry.id, role: .roaster)
                        } label: {
                            FlagView(isoCode: roasterCountry.isoCode).font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    } else {
                        FlagView(isoCode: roasterCountry?.isoCode).font(.system(size: 13))
                    }

                    if FeatureFlags.tapNavigatesToEntityPages {
                        NavigationLink {
                            RoasterPageView(roasterID: roaster.id)
                        } label: {
                            roasterNameLine(roaster)
                        }
                        .buttonStyle(.plain)
                    } else {
                        roasterNameLine(roaster)
                    }

                    Spacer()
                    if FeatureFlags.tapNavigatesToEntityPages {
                        Image(systemName: Symbols.chevronRight)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.neutral700)
                    }
                }
            }
        }
    }

    /// Blue name, always — the roaster row's one place blue always appears,
    /// same as the rating. The "your best roaster" suffix only shows for the
    /// single #1 roaster (`topRoasterIDs().first`), not mere membership in the
    /// top set — that distinction is `CoffeeRowView`'s own note about itself.
    private func roasterNameLine(_ roaster: Roaster) -> some View {
        HStack(spacing: 4) {
            Text(roaster.name)
                .font(.system(size: 13, weight: Theme.Weight.semibold))
                .foregroundStyle(Theme.Colors.accent)
            if let average = bestRoasterAverage(for: roaster) {
                Text("· your best roaster, \(String(format: "%.1f", average)) avg")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
        }
    }

    private func bestRoasterAverage(for roaster: Roaster) -> Double? {
        guard let best = store.index.topRoasterIDs().first, best.id == roaster.id else { return nil }
        return best.average
    }

    private var titleBlock: some View {
        Text(coffee.displayTitle(vocabulary: vocabulary))
            .font(.system(size: 27, weight: Theme.Weight.heavy))
            .tracking(-0.81)
            .foregroundStyle(Theme.Colors.text)
    }

    private var pillRow: some View {
        let origins = coffee.allOriginCountries(vocabulary: vocabulary)
        return WrapLayout() {
            // A blend gets a "Blend" marker plus one pill per origin country; a
            // single-origin coffee just gets its one country pill. Either way,
            // every country pill is its own tap target into the origin page.
            // Blend/decaf pills keep their pre-redesign styling (handoff
            // §Screen 2: "Blend/decaf pills as today").
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
            // No tinted process capsule here (Definition of done) — a plain
            // neutral pill, and omitted entirely when the profile is unknown
            // rather than rendering "Unknown" (missing fields omit their row).
            if let profile = coffee.profile {
                DetailPill(text: profile.displayName)
            }
            if let altitude = coffee.altitudeLabel {
                DetailPill(text: altitude)
            }
            if let weight = coffee.weightLabel {
                DetailPill(text: weight)
            }
            if coffee.isDecaf {
                DecafBadge()
            }
        }
    }

    @ViewBuilder
    private func originPill(for country: Country) -> some View {
        let average = topOriginAverage(for: country)
        let text = (country.isoCode.flatMap { $0.flagEmoji } ?? "🏳️") + " " + country.name
            + (average.map { " " + String(format: "%.1f", $0) } ?? "")
        // Pushback #7: the origin flag (folded into this pill's text) opens the
        // origin-country page.
        if FeatureFlags.tapNavigatesToEntityPages {
            NavigationLink {
                CountryPageView(countryID: country.id, role: .origin)
            } label: {
                DetailPill(text: text, isAccent: average != nil)
            }
            .buttonStyle(.plain)
        } else {
            DetailPill(text: text, isAccent: average != nil)
        }
    }

    /// `nil` unless this country is in the user's top-origin set (design
    /// handoff §Row's "top-preference rule" — ≥5 rated bags, highest average).
    private func topOriginAverage(for country: Country) -> Double? {
        store.index.topOriginCountryIDs().first { $0.id == country.id }?.average
    }

    // MARK: - Price block

    /// Design handoff §Screen 2: `PRICE`/`PER 100 G` stat pair beside the
    /// five-pill value meter — replaces the old fact-row price lines.
    @ViewBuilder
    private var priceBlock: some View {
        if coffee.priceLabel != nil || coffee.pricePer100gEur != nil {
            HStack(alignment: .top) {
                HStack(alignment: .top, spacing: 24) {
                    if let priceLabel = coffee.priceLabel {
                        priceStat(label: "PRICE", value: priceLabel)
                    }
                    if let pricePer100gEur = coffee.pricePer100gEur {
                        priceStat(label: "PER 100 G", value: pricePer100gEur.formatted(.currency(code: "EUR")))
                    }
                }
                Spacer(minLength: 12)
                if let valueRating = store.index.valueBand(for: coffee) {
                    VStack(alignment: .trailing, spacing: 4) {
                        valueMeter(valueRating)
                        if let band = valueRating.band {
                            Text(verdictLabel(band))
                                .font(.system(size: 10, weight: Theme.Weight.semibold))
                                .tracking(0.8)
                                .foregroundStyle(band == .great ? Theme.Colors.accent : Theme.Colors.neutral700)
                        }
                    }
                }
            }
        }
    }

    private func priceStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: Theme.Weight.semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.neutral700)
            Text(value)
                .font(.system(size: 22, weight: Theme.Weight.heavy))
                .foregroundStyle(Theme.Colors.text)
        }
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

    /// `.overpaid` replaces the old `.pricey` (`UPDATE_BRIEF.md` §B): the point
    /// is that you rated it low for what it cost, not that it was expensive.
    private func verdictLabel(_ band: ValueRating.Band) -> String {
        switch band {
        case .great: return "GREAT VALUE"
        case .fair: return "FAIR VALUE"
        case .overpaid: return "OVERPAID"
        }
    }

    private var factRows: [FactRow] {
        var rows: [FactRow] = []
        rows.append(FactRow(label: "Purchased", value: PlainDateFormatting.exact(coffee.purchasedOn)))
        if let roastedOn = coffee.roastedOn {
            rows.append(FactRow(label: "Roasted", value: PlainDateFormatting.exact(roastedOn)))
        }
        if let farm = coffee.originFarm(vocabulary: vocabulary) {
            rows.append(FactRow(label: "Farm", value: farm.name))
        }
        return rows
    }

    // MARK: - Flavour profile (#79/#81, folds in #82)

    @ViewBuilder
    private var flavourProfileSection: some View {
        if let chips = flavourChips {
            VStack(alignment: .leading, spacing: 8) {
                Text("FLAVOUR PROFILE")
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.neutral700)
                WrapLayout() {
                    ForEach(chips, id: \.self) { note in
                        Text(note)
                            .font(.system(size: 11, weight: Theme.Weight.semibold))
                            .foregroundStyle(Theme.Colors.accent800)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.Colors.accent100, in: Capsule())
                    }
                }
                Text("Read from the roaster's own copy on the bag.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
        }
    }

    /// `Coffee.flavorNotes` is a short comma-separated string ("ciocolată,
    /// vișine, prune uscate", #79/#80) — split into individual chips, `nil`
    /// when absent or the scan found nothing (an empty-string sentinel means
    /// "scanned, no notes stated", same as elsewhere in the app).
    private var flavourChips: [String]? {
        guard let raw = coffee.flavorNotes else { return nil }
        let chips = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return chips.isEmpty ? nil : chips
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            flavourProfileSection
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
                .textCase(.uppercase)
                .font(.system(size: 10, weight: Theme.Weight.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.neutral700)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.text)
        }
    }
}

/// The redesigned pill row's plain (non-tinted) pill — process/altitude/
/// weight always, origin only when it isn't a top-preference country
/// (`originPill(for:)`'s own `isAccent` branch covers that case).
private struct DetailPill: View {
    let text: String
    var isAccent: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isAccent ? Theme.Colors.accent700 : Theme.Colors.text)
            .background(isAccent ? Theme.Colors.accent100 : Theme.Colors.neutral100, in: Capsule())
    }
}

