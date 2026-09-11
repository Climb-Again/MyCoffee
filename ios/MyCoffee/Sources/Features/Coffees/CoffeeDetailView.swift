import SwiftUI
import UIKit

/// The coffee detail page — 2a redesign (`#88`,
/// `design/coffees_redesign/README.md` §Screen 2, folds in `#82`), header
/// reworked per `HEADER_UPDATE.md` (#141-#147): a 300pt full-bleed hero with
/// the system back button (never `.navigationBarBackButtonHidden` + a
/// custom overlay, which killed edge-swipe-back and duplicated the arrow
/// the one time this was tried) plus bare white favourite/share/edit
/// controls on the photo, a white card overlapping it by 20pt with a
/// roaster-logo medallion astride the seam, then roaster row → title →
/// rating, pill row, a price block with the value meter, fact rows, a
/// flavour-profile section, note blocks, the FROM THE ROASTER facts grid,
/// then rating-ordered rails.
struct CoffeeDetailView: View {
    private let initialCoffee: Coffee
    @EnvironmentObject private var store: CoffeeStore
    @ObservedObject private var reviewCache = ReviewFeedCache.shared
    @State private var showReview = false
    @State private var showEdit = false
    @State private var showFullPhoto = false
    @State private var showFullTextSheet = false
    @State private var showBrewLab = false

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
        // No ToolbarItems here any more (`HEADER_UPDATE.md` §1): favourite/
        // share/edit are bare overlays on the photo now, not toolbar-hosted
        // circles. The back chevron is left entirely to the system — it is
        // NOT rebuilt as a fourth bare overlay control, even though §1 groups
        // it with the other three, because a custom overlay back button
        // paired with `.navigationBarBackButtonHidden` is exactly what killed
        // edge-swipe-back and duplicated the arrow the one time this was
        // tried (see the file-level doc comment). The automatic system back
        // button over the transparent bar is the safe, already-working
        // mechanism, so it stays untouched; its styling won't hit §1's exact
        // stroke/shadow spec, which is a known, deliberate partial gap.
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
        .sheet(isPresented: $showBrewLab) {
            BrewLabSheet(coffeeId: coffee.id)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showFullTextSheet) {
            fullTextSheet
        }
    }

    /// The roaster's raw scraped copy, verbatim and unedited (§5's "one tap
    /// away" link), regardless of how many facts `RoasterFactParser` managed
    /// to lift out of it.
    private var fullTextSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rawTextBlocks, id: \.label) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            if rawTextBlocks.count > 1 {
                                Text(block.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(block.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Full text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFullTextSheet = false }
                }
            }
        }
    }

    private var hasPhoto: Bool {
        (coffee.images?.display).flatMap(URL.init(string:)) != nil
    }

    /// §1: bare white heart, no chip/circle behind it. Favourited vs not
    /// differs only by outline↔fill — never a coloured background.
    private var favoriteButton: some View {
        Button {
            store.toggleFavorite(coffee)
        } label: {
            bareIcon(coffee.isFavorite ? Lucide.heartFill : Lucide.heart, size: 22)
        }
    }

    /// One bare white photo control (§1): no capsule/circle/material/fill,
    /// just the icon, tinted white with a drop shadow for legibility, inside
    /// a 44×44 hit area.
    private func bareIcon(_ name: String, size: CGFloat) -> some View {
        AppIcon(name: name, size: size)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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
        // Tap the (cropped) hero to see the whole photo full-screen — the
        // old bottom-trailing expand button is gone (§1), this gesture is
        // now the only way in, same as before.
        .contentShape(Rectangle())
        .onTapGesture {
            if hasPhoto { showFullPhoto = true }
        }
        .overlay(alignment: .top) {
            // §1: one top scrim, no bottom scrim — keeps the bare white
            // controls legible over a pale bag.
            LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 126)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            photoControls
        }
    }

    /// The trailing three bare controls, `HStack(spacing: 0)` per §1. All on
    /// one baseline 50pt from the top of the frame — a 44pt-tall hit area
    /// centred there sits 28pt from the top, hence the padding below.
    private var photoControls: some View {
        HStack(spacing: 0) {
            Spacer()
            favoriteButton
            ShareLink(item: coffee.displayTitle(vocabulary: vocabulary)) {
                bareIcon(Lucide.share, size: 21)
            }
            Button {
                showEdit = true
            } label: {
                bareIcon(Lucide.pencil, size: 21)
            }
        }
        .padding(.top, 28)
        .padding(.trailing, 6)
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
            // §3: roaster (medallion overlay below) → title → rating.
            roasterHeaderRow
            titleBlock
            ratingHeader
            pillRow
            priceBlock
            if !factRows.isEmpty {
                FactRowsList(rows: factRows)
            }
            brewLabSection
            notesSection
            fromTheRoasterSection
            railsSection
            // §7(b): scrollable trailing space so the last rail's cards clear
            // the (glass, native — `RootTabView`) tab bar rather than sitting
            // flush against it. No API for the live bar height here, so this
            // is a fixed approximation of "bar height + 16pt".
            Color.clear.frame(height: 84)
        }
        .padding(.horizontal, 22)
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
        // §6: the sheet itself carries no shadow — its corner radius and this
        // -20pt overlap read as depth on their own. Must not `.clipped()`, or
        // the medallion's top 40pt and its ring get sliced (§2).
        .offset(y: -20)
        .overlay(alignment: .topLeading) {
            if let roaster = coffee.roaster(vocabulary: vocabulary) {
                RoasterLogoTile(logoUrl: roaster.logoUrl)
                    .offset(x: 22, y: -40)
            }
        }
    }

    private var ratingHeader: some View {
        HStack(alignment: .center) {
            if let rating = coffee.rating {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 34, weight: Theme.Weight.heavy))
                        .tracking(-1.02)
                        .foregroundStyle(Theme.Colors.accent)
                    starRow(for: rating)
                }
            } else {
                Text("Unrated")
                    .font(.system(size: 22, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            Spacer()
            if coffee.reviewState == "unextracted" {
                // #131: nothing to review yet — the coffee was quick-created
                // and the background extraction pass hasn't landed, so this
                // replaces (never combines with) the review pill below.
                extractingPill
            } else if coffee.hasOpenReview && reviewCache.hasReviewableTasks(for: coffee.id) {
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

    /// Non-interactive — unlike `reviewPillText`'s button, there's nothing to
    /// review yet, just a wait.
    private var extractingPill: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("Extracting…")
                .font(.system(size: 11, weight: Theme.Weight.semibold))
        }
        .foregroundStyle(Theme.Colors.neutral700)
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minHitTarget)
        .background(Theme.Colors.neutral100, in: Capsule())
    }

    /// §4: the fractional star (e.g. 4.1 → fifth star 10% filled) is masked
    /// to `rating - index` clamped to 0...1, not just special-cased for the
    /// fifth position — any rating's partial star fills the same way.
    private func starRow(for rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let fraction = min(max(rating - Double(index), 0), 1)
                ZStack(alignment: .leading) {
                    Image(systemName: Symbols.star)
                        .foregroundStyle(Theme.Colors.neutral300)
                    if fraction > 0 {
                        Image(systemName: Symbols.starFill)
                            .foregroundStyle(Theme.Colors.accent)
                            .mask(alignment: .leading) {
                                GeometryReader { proxy in
                                    Rectangle().frame(width: proxy.size.width * fraction)
                                }
                            }
                    }
                }
                .font(.system(size: 13))
                .frame(width: 13, height: 13)
            }
        }
    }

    /// §3's medallion+roaster row: the medallion itself is `card`'s own
    /// overlay (it must be able to draw outside this row's bounds, over the
    /// photo above), so this only reserves the 100pt leading gap (86 tile +
    /// 14 gap) and lays out the two text lines beside it. Per §3, the whole
    /// row — medallion included — taps to the roaster page; this supersedes
    /// pushback #7's separate flag→country tap target for this one row.
    @ViewBuilder
    private var roasterHeaderRow: some View {
        if let roaster = coffee.roaster(vocabulary: vocabulary) {
            let roasterCountry = coffee.roasterCountry(vocabulary: vocabulary)
            if FeatureFlags.tapNavigatesToEntityPages {
                NavigationLink {
                    RoasterPageView(roasterID: roaster.id)
                } label: {
                    roasterHeaderContent(roaster: roaster, roasterCountry: roasterCountry)
                }
                .buttonStyle(.plain)
            } else {
                roasterHeaderContent(roaster: roaster, roasterCountry: roasterCountry)
            }
        }
    }

    private func roasterHeaderContent(roaster: Roaster, roasterCountry: Country?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                FlagView(isoCode: roasterCountry?.isoCode).font(.system(size: 13))
                Text(roaster.name)
                    .font(.system(size: 13, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                if FeatureFlags.tapNavigatesToEntityPages {
                    AppIcon(name: Lucide.chevronRight, size: 15)
                        .foregroundStyle(Theme.Colors.neutral700)
                }
                Spacer(minLength: 0)
            }
            // "Your best roaster" only for the single #1 roaster
            // (`topRoasterIDs().first`), not mere top-set membership.
            if let average = bestRoasterAverage(for: roaster) {
                Text("Your best roaster · \(String(format: "%.1f", average)) avg")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
        }
        .padding(.leading, 100)
        .frame(minHeight: 54, alignment: .bottom)
        .padding(.bottom, 6)
    }

    private func bestRoasterAverage(for roaster: Roaster) -> Double? {
        guard let best = store.index.topRoasterIDs().first, best.id == roaster.id else { return nil }
        return best.average
    }

    private var titleBlock: some View {
        Text(coffee.displayTitle(vocabulary: vocabulary))
            .font(.system(size: 29, weight: Theme.Weight.heavy))
            .tracking(-0.87)
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
                                .font(.system(size: 10, weight: band == .great ? Theme.Weight.bold : Theme.Weight.semibold))
                                .tracking(0.8)
                                .foregroundStyle(bandColor(band))
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
        let tone = bandColor(rating.band)
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: Theme.Radius.pill)
                    .fill(pip < rating.pillCount ? tone : tone.opacity(0.15))
                    .frame(width: 8, height: 4)
            }
        }
    }

    /// One shared depth tone per band (#186, `VALUE_BAND_UPDATE.md`) — the
    /// lit pills, the unlit track (this colour at 15%) and the verdict text
    /// all read off this. Verbatim-copied at `CoffeeRowView.bandColor` until
    /// #181 dedupes `valueMeter`/`verdictLabel` into one view.
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

    /// One word per pill (#105) — the label and the meter are the same five-step
    /// scale, so they cannot disagree the way 4-pills-FAIR and 2-pills-FAIR did.
    /// `.overpaid` also replaces the old `.pricey` (`UPDATE_BRIEF.md` §B): the
    /// point is that you rated it low for what it cost, not that it was dear.
    /// #113 moved the wording onto `ValueRating.Band` itself so the filter
    /// pills and the `.value` sort headers print exactly what the meter does.
    private func verdictLabel(_ band: ValueRating.Band) -> String { band.label }

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

    // MARK: - Brew lab (#157, PLAN.md §14)

    /// A four-cell glance: what won for recipe / device / grind / temp. The
    /// point of the whole feature is that the answer to "how do I brew this
    /// one" is on the coffee's own page, not in a note you have to read.
    ///
    /// Hidden entirely on an `unextracted` placeholder — a coffee that is
    /// still being read off its bag has nothing to brew against yet, and the
    /// quick-create flow (#131) leaves those on screen for a while.
    @ViewBuilder
    private var brewLabSection: some View {
        if coffee.reviewState != "unextracted" {
            VStack(alignment: .leading, spacing: 12) {
                Text("BREW LAB")
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.neutral700)

                if brewHasAnyTrial {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(BrewKind.allCases, id: \.self) { kind in
                            brewCell(kind)
                        }
                    }
                } else {
                    Text("Log what you brewed with →")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { showBrewLab = true }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Open the brew lab for this coffee")
        }
    }

    private var brewHasAnyTrial: Bool { !coffee.triedBrewOptionIds.isEmpty }

    /// Winner's label if there is one, else "n tried", else an em dash — the
    /// omit-not-"N/A" rule, but a 2×2 grid needs all four cells present or
    /// the kinds stop being comparable at a glance.
    @ViewBuilder
    private func brewCell(_ kind: BrewKind) -> some View {
        let winner = store.index.bestBrewOption(for: coffee, kind: kind)
        let triedCount = store.index.triedBrewOptions(for: coffee, kind: kind).count
        VStack(alignment: .leading, spacing: 2) {
            Text(kind.displayName.uppercased())
                .font(.system(size: 10, weight: Theme.Weight.semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.neutral700)
            if let winner {
                HStack(spacing: 4) {
                    Image(systemName: Symbols.trophyFill)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(winner.chipLabel)
                        .font(.system(size: 13, weight: Theme.Weight.semibold))
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                }
            } else if triedCount > 0 {
                Text("\(triedCount) tried")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.neutral700)
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The raw scraped text (title / caption / description) exactly as
    /// ingested — the curated `desc_*` note blocks above are empty on the
    /// freshly-extracted "probe" coffees, so this is what actually carries
    /// their full content. Also `RoasterFactParser`'s only input.
    private var rawTextBlocks: [(label: String, text: String)] {
        [
            ("Title", coffee.rawTitle),
            ("Caption", coffee.rawCaption),
            ("Description", coffee.rawDescription)
        ].compactMap { label, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (label, value)
        }
    }

    private var roasterFacts: [RoasterFact] {
        RoasterFactParser.extract(from: rawTextBlocks.map(\.text))
    }

    /// §5: replaces the old "Full text" link with the FROM THE ROASTER
    /// facts grid, falling back to a clamped excerpt (same link) whenever
    /// parsing lifted fewer than two facts out of the roaster's copy.
    @ViewBuilder
    private var fromTheRoasterSection: some View {
        if !rawTextBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("FROM THE ROASTER")
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.neutral700)

                if roasterFacts.count >= 2 {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())],
                        alignment: .leading, spacing: 12
                    ) {
                        ForEach(roasterFacts) { fact in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.key)
                                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.Colors.neutral700)
                                Text(fact.value)
                                    .font(.system(size: 13, weight: Theme.Weight.semibold))
                                    .foregroundStyle(Theme.Colors.text)
                            }
                        }
                    }
                } else {
                    Text(rawTextBlocks[0].text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.neutral700)
                        .lineLimit(2)
                }

                Button {
                    showFullTextSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Read the full text")
                            .font(.system(size: 12, weight: Theme.Weight.semibold))
                        AppIcon(name: Lucide.chevronRight, size: 14)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
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

