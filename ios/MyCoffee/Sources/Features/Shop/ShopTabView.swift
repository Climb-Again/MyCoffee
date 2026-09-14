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
            ContentUnavailableView(
                "Nothing shortlisted",
                systemImage: Symbols.tabShopFallback,
                description: Text("Coffees you evaluate with the browser extension show up here for 30 days.")
            )
        } else {
            List(store.shortlist) { entry in
                ShortlistRow(entry: entry)
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
    @EnvironmentObject private var store: CoffeeStore
    let entry: ShortlistEntry

    /// "IN YOUR LIBRARY" — the single most useful thing a shortlist row can
    /// say. Matched on roaster name against the same vocab the extension
    /// matches against, so the two agree.
    private var isOwnedRoaster: Bool {
        guard let roaster = entry.roasterName?.lowercased(), !roaster.isEmpty else { return false }
        return store.index.vocabulary.roasters.values.contains { $0.name.lowercased() == roaster }
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
                    Text(String(format: "€%.1f/100g", per100))
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
