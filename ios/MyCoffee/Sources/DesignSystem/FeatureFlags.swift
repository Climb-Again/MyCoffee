import Foundation

/// One-line-revert switches for behaviour that depends on screens not built
/// yet. Both flipped `true` now that #28 (roaster/country entity pages) has
/// landed; keep them as a fast revert if the entity pages need to come back
/// out.
enum FeatureFlags {
    /// PLAN.md pushback #7: roaster **name** row -> roaster page; roaster
    /// flag -> roaster-country page; origin flag -> origin-country page.
    static let tapNavigatesToEntityPages = true

    /// PLAN.md §6.3: rail "More" goes to the roaster/country entity page
    /// rather than a bare filtered list.
    static let railMoreGoesToEntityPage = true
}
