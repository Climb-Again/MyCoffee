import SwiftUI
import UIKit

/// #195(b) — the Shop tab: the browser extension's shortlist (#187 → #194),
/// on the phone.
///
/// This tab is only possible because #194 moved the shortlist server-side: the
/// iOS app has no way to read `chrome.storage.local`, so before that the list
/// existed solely inside whichever browser produced it.
///
/// **The server's rows are rendered as-is** — same order, same score. The
/// extension already ranks and prunes them (#196's manual adjustment, #197's
/// 30-day window from *add* time, #199's re-blended score), and a second
/// ranking here would be a second definition of one list: the phone and the
/// browser would disagree about which bag is top, with no way to tell which
/// was right. Same reasoning as #199's server/extension contract test.
struct ShopTabView: View {
    @EnvironmentObject private var store: CoffeeStore

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Shop")
                .navigationBarTitleDisplayMode(.large)
                .refreshable { await store.loadShortlist() }
        }
        .task { await store.loadShortlist() }
    }

    /// A `@ViewBuilder` property, deliberately NOT a `Group { … }`: a bare
    /// `Group` wrapping these three branches made Swift pick the
    /// `TableColumnBuilder` overload of `Group.init` and fail with "generic
    /// parameter 'R' could not be inferred" (run #136). `@ViewBuilder` pins the
    /// result-builder, so there is nothing to guess.
    @ViewBuilder
    private var content: some View {
        if let error = store.shortlistError, store.shortlist.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load your shortlist", systemImage: Symbols.syncFailed)
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await store.loadShortlist() } }
            }
        } else if store.shortlist.isEmpty {
            // Brief v2 §3 States, verbatim: "Nothing shortlisted yet." 17 pt,
            // then 12 pt neutral-700, "No install button — the extension is
            // live and installs from the browser, not from here." No
            // illustration, so this is a plain VStack rather than a
            // ContentUnavailableView (which always draws a glyph).
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing shortlisted yet.")
                    .font(.system(size: 17, weight: .semibold))
                Text("Save coffees from roaster shops with the MyCoffee extension.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 8)
        } else {
            // #217(a): roasters actually in the library, not the whole
            // canonical vocabulary — see `ShortlistRow.isOwnedRoaster`.
            // Computed once per list build rather than per row.
            let ownedRoasterNames = Set(
                store.index.coffees.compactMap { coffee in
                    coffee.roasterId.flatMap { store.index.vocabulary.roasters[$0]?.name.lowercased() }
                }
            )
            List(store.shortlist) { entry in
                ShortlistRow(entry: entry, ownedRoasterNames: ownedRoasterNames)
                    .plainListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// Mirrors `CoffeeRowView`'s field layout (the 2a redesign) so the two lists
/// read as one app: image · UPPERCASE ROASTER / title / origin · a
/// right-aligned number column. The fit score takes the rating's slot, because
/// that is the number this surface knows — the library shows what he rated it,
/// this shows how well it fits.
private struct ShortlistRow: View {
    let entry: ShortlistEntry
    /// Roaster names (lowercased) with at least one bag in the library —
    /// computed once for the whole list by `ShopTabView`, not per row.
    let ownedRoasterNames: Set<String>

    /// "IN YOUR LIBRARY" — the single most useful thing a shortlist row can
    /// say. #217(a): used to match against the FULL canonical roaster
    /// vocabulary (every roaster the extraction pipeline knows about, not
    /// just Radu's own), so a shortlisted bag from a roaster he has never
    /// bought from still lit up the tag. `ownedRoasterNames` is scoped to
    /// roasters that actually appear in his library, matching what the
    /// extension itself would call owned in spirit — the precise per-bag
    /// `ownedTitle` match the extension uses isn't in the synced payload yet
    /// (see #219), so roaster-level is the closest available proxy.
    private var isOwnedRoaster: Bool {
        guard let roaster = entry.roasterName?.lowercased(), !roaster.isEmpty else { return false }
        return ownedRoasterNames.contains(roaster)
    }

    /// #217(b): mirrors the extension's own day-since-roast bucket
    /// (`extension/history.js` `roastLabel`), computed from the same
    /// `roastedOn` date already synced onto the entry.
    private var roastDaysAgo: Int? {
        guard let roastedOn = entry.roastedOn, let date = PlainDate(string: roastedOn) else { return nil }
        return Calendar.utc.dateComponents([.day], from: date.utcMidnight, to: Date()).day
    }

    private var roastLabel: String? {
        guard let days = roastDaysAgo else { return nil }
        if days <= 0 { return "roasted today" }
        if days < 70 { return "roasted \(days)d ago" }
        return "roasted ~\(Int((Double(days) / 30).rounded()))mo ago"
    }

    /// Three-tier bucket rather than the extension's continuous hue ramp — a
    /// list row doesn't carry the same "why did this lose points" burden the
    /// popup chip does. Breakpoints (14/60 days) match
    /// `ROAST_GREEN_DAYS`/`ROAST_RED_DAYS` in `extension/history.js`.
    private var roastLabelColor: Color? {
        guard let days = roastDaysAgo else { return nil }
        switch days {
        case ..<14: return .green
        case 14..<60: return .orange
        default: return .red
        }
    }

    /// #217(b): "seen Nh ago" — mirrors `relativeTime` in
    /// `extension/history.js` (floor at the minute, round above it).
    private var seenLabel: String? {
        guard let savedDate = entry.savedDate else { return nil }
        let mins = max(0, Int(Date().timeIntervalSince(savedDate) / 60))
        if mins < 1 { return "seen just now" }
        if mins < 60 { return "seen \(mins)m ago" }
        let hours = Int((Double(mins) / 60).rounded())
        if hours < 24 { return "seen \(hours)h ago" }
        let days = Int((Double(hours) / 24).rounded())
        return days == 1 ? "seen yesterday" : "seen \(days)d ago"
    }

    /// Two independently-coloured segments concatenated via `Text +`, so the
    /// roast half can carry `roastLabelColor` without tinting "seen" too.
    private var freshnessLine: Text? {
        let roast = roastLabel.map { Text($0).foregroundColor(roastLabelColor ?? Theme.Colors.neutral700) }
        let seen = seenLabel.map { Text($0).foregroundColor(Theme.Colors.neutral700) }
        switch (roast, seen) {
        case (let r?, let s?): return r + Text(" · ").foregroundColor(Theme.Colors.neutral700) + s
        case (let r?, nil): return r
        case (nil, let s?): return s
        case (nil, nil): return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedImage(urlString: entry.imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.1)
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                if let roaster = entry.roasterName {
                    Text(roaster.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(entry.title ?? entry.url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let origin = entry.originName {
                    Text(origin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let freshnessLine {
                    freshnessLine
                        .font(.caption2)
                }
                if isOwnedRoaster {
                    Text("IN YOUR LIBRARY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let score = entry.displayScore {
                    Text("\(score)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(score >= 60 ? Theme.Colors.accent : Color.primary)
                }
                if let adjustment = entry.adjustment, adjustment != 0 {
                    Text("\(adjustment > 0 ? "+" : "")\(adjustment)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                if let per100 = entry.pricePer100gEur {
                    // #217(c): match the extension's 2-decimal, no-space
                    // format ("€7.56/100g") — the app was rounding to 1.
                    Text(String(format: "€%.2f/100g", per100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        // Tap opens the roaster's page in Safari — the point of a shortlist is
        // to go and buy the bag.
        .onTapGesture {
            if let url = URL(string: entry.url) { UIApplication.shared.open(url) }
        }
    }
}
