import Foundation

/// One-line-revert switches for behaviour that depends on screens not built
/// yet. Both default `false` until the dependent screen (roaster/country
/// entity pages, #28) lands.
enum FeatureFlags {
    /// PLAN.md pushback #7: roaster **name** row -> roaster page; roaster
    /// flag -> roaster-country page; origin flag -> origin-country page.
    static let tapNavigatesToEntityPages = false

    /// PLAN.md §6.3: rail "More" goes to the roaster/country entity page
    /// rather than a bare filtered list.
    static let railMoreGoesToEntityPage = false
}
