import SwiftUI

/// Redesign v3 §11 (#111): the app's chrome icons are **Lucide** outlines
/// (1.7pt stroke, round caps), vendored as template SVG imagesets in
/// `Resources/Assets.xcassets/lucide-*.imageset` from Radu's supplied files.
/// These are asset names, not SF Symbol names — render them with `AppIcon`,
/// which tints them via the current `foregroundStyle`/tab tint. Only the
/// active-favourite heart is filled; everything else is an outline.
enum Lucide {
    static let coffee = "lucide-coffee"
    static let circlePlus = "lucide-circle-plus"
    static let barChart3 = "lucide-bar-chart-3"
    static let slidersHorizontal = "lucide-sliders-horizontal"
    static let settings = "lucide-settings"
    static let heart = "lucide-heart"
    static let heartFill = "lucide-heart-fill"
    static let chevronRight = "lucide-chevron-right"
    static let chevronLeft = "lucide-chevron-left"
    static let share = "lucide-share"
    static let pencil = "lucide-pencil"
    static let search = "lucide-search"
}

/// A Lucide (or any template) asset image sized explicitly — asset images
/// don't scale with `.font()` the way SF Symbols do, so callers pass the size
/// (§11: 22pt nav, 25pt tab, 14–19pt inline). Colour comes from the ambient
/// `foregroundStyle`/tint, same as an SF Symbol.
struct AppIcon: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Every SF Symbol name used by the app lives here. They're strings the
/// compiler can't check, and with no local Xcode a typo renders as a silent
/// blank rather than a build error (PLAN.md §6.6).
enum Symbols {
    // Tabs (Redesign v3 §3 — the `+` is a middle tab item, not a floating
    // circle; §11 later swaps these for Lucide outlines).
    static let tabCoffees = "cup.and.saucer"
    static let tabInsights = "chart.bar"
    static let tabAdd = "plus.circle.fill"
    static let tabReview = "checklist"

    // Listing
    static let filter = "line.3.horizontal.decrease.circle"
    static let filterFilled = "line.3.horizontal.decrease.circle.fill"
    // Redesign v3 §1: the nav-bar sort control is `sliders-horizontal`.
    static let sort = "slider.horizontal.3"
    static let search = "magnifyingglass"
    static let heart = "heart"
    static let heartFill = "heart.fill"
    static let starFill = "star.fill"
    static let star = "star"
    static let chevronRight = "chevron.right"
    static let chevronBackward = "chevron.backward"
    static let settings = "gearshape"
    static let share = "square.and.arrow.up"
    static let close = "xmark"
    static let rotate = "rotate.right"

    // Process tags
    static let processDecaf = "moon.zzz.fill"
    static let processNatural = "sun.max.fill"
    static let processWashed = "drop.fill"
    static let processAnaerobic = "seal.fill"
    static let processCoFermented = "arrow.triangle.merge"
    static let processExperimental = "testtube.2"
    static let processUnknown = "questionmark.circle"

    // Detail / fact rows
    static let calendar = "calendar"
    static let eurosign = "eurosign.circle"
    static let mountain = "mountain.2"
    static let scale = "scalemass"
    static let needsReview = "exclamationmark.triangle.fill"

    // Empty / misc states
    static let emptyCup = "cup.and.saucer"

    // Insights (#28)
    static let dataQuality = "checkmark.seal"
    static let zscoreToggle = "chart.line.uptrend.xyaxis"
    static let insightsEmpty = "chart.bar.xaxis"
    static let brief = "newspaper"

    // Review queue (#27)
    static let reviewCountry = "globe"
    static let reviewRoaster = "storefront"
    static let reviewFarm = "leaf"
    static let reviewAccept = "checkmark.circle.fill"
    static let reviewUndo = "arrow.uturn.backward.circle"
    static let reviewRule = "link"
    static let reviewOther = "square.and.pencil"
    static let reviewZoom = "arrow.up.left.and.arrow.down.right"
    static let reviewPhotoMissing = "photo"
    static let reviewEmpty = "checkmark.circle"

    // Edit sheet (#42)
    static let edit = "pencil"
    static let pickerSelected = "checkmark"

    // What's New (#47)
    static let whatsNew = "sparkles"
    static let whatsNewEmpty = "tray"
    static let whatsNewUnavailable = "wifi.exclamationmark"

    // Add Coffee wizard (#77)
    static let wizardAdd = "plus"
    static let wizardPhotos = "photo.on.rectangle.angled"
    static let wizardCamera = "camera.fill"
}
