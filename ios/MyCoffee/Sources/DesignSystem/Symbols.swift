import Foundation

/// Every SF Symbol name used by the app lives here. They're strings the
/// compiler can't check, and with no local Xcode a typo renders as a silent
/// blank rather than a build error (PLAN.md §6.6).
enum Symbols {
    // Tabs
    static let tabCoffees = "cup.and.saucer.fill"
    static let tabInsights = "chart.bar.fill"
    static let tabReview = "checklist"

    // Listing
    static let filter = "line.3.horizontal.decrease.circle"
    static let filterFilled = "line.3.horizontal.decrease.circle.fill"
    static let sort = "arrow.up.arrow.down.circle"
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
}
