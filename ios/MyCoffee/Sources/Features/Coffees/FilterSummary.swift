import Foundation

/// A short, human-readable description of what the active filter is actually
/// doing — the line Radu asked for under the search bar (#149, 2026-09-07:
/// "show what is filtered"). The chips above it only cover the ≤7 top-filter
/// shortcuts, so a filter built in the sheet (origin + process + a rating
/// band) previously showed nothing but a bare "37 of 411 bags".
///
/// Deliberately lossy: it names *values*, not dimensions ("Ethiopia · Washed ·
/// 4.5+ ★", not "Origin: Ethiopia · Process: Washed"), because the values are
/// what you recognise at a glance and the line has one row to say it in.
/// Anything past `maxTerms` collapses into "+N more" rather than wrapping.
enum FilterSummary {
    static func text(for filter: CoffeeFilter, vocabulary: Vocabulary, maxTerms: Int = 4) -> String? {
        var terms: [String] = []

        // The query is shown in the search field itself, so it is not repeated
        // here — every other constraint is invisible without this line.
        for id in filter.roasterIDs.sorted() {
            terms.append(vocabulary.roasters[id]?.name ?? "Roaster")
        }
        for id in filter.originCountryIDs.sorted() {
            terms.append(vocabulary.countries[id]?.name ?? "Origin")
        }
        for id in filter.roasterCountryIDs.sorted() {
            terms.append((vocabulary.countries[id]?.name).map { "Roasted in \($0)" } ?? "Roaster country")
        }
        for id in filter.farmIDs.sorted() {
            terms.append(vocabulary.farms[id]?.name ?? "Farm")
        }
        for profile in filter.profiles.sorted(by: { $0.displayName < $1.displayName }) {
            terms.append(profile.displayName)
        }
        for band in filter.ratingBands.sorted(by: { $0.label < $1.label }) {
            terms.append(band.label)
        }
        for band in filter.valueBands.sorted(by: { $0.rawValue > $1.rawValue }) {
            terms.append(band.label.capitalizedFirstWordOnly)
        }
        for band in filter.priceBands.sorted(by: { $0.label < $1.label }) {
            terms.append(band.label)
        }
        for band in filter.pricePer100gBands.sorted(by: { $0.label < $1.label }) {
            terms.append(band.label + " / 100 g")
        }
        for band in filter.altitudeBands.sorted(by: { $0.label < $1.label }) {
            terms.append(band.label)
        }
        for id in filter.brewDeviceIDs.sorted() + filter.brewRecipeIDs.sorted()
            + filter.brewGrindIDs.sorted() + filter.brewTempIDs.sorted() {
            terms.append(vocabulary.brewOptions[id]?.label ?? "Brew")
        }
        for year in filter.years.sorted(by: >) {
            terms.append("\(year)")
        }
        if let window = filter.relativeWindow {
            terms.append(window.label)
        }
        if filter.favoritesOnly { terms.append("Favourites") }
        if let isDecaf = filter.isDecaf { terms.append(isDecaf ? "Decaf" : "Not decaf") }
        // The "missing this field" buckets read as a task, not a value.
        for dimension in filter.unknownDimensions.sorted(by: { $0.title < $1.title }) {
            terms.append("No \(dimension.title.lowercased())")
        }

        guard !terms.isEmpty else { return nil }
        guard terms.count > maxTerms else { return terms.joined(separator: " · ") }
        let shown = terms.prefix(maxTerms).joined(separator: " · ")
        return "\(shown) · +\(terms.count - maxTerms) more"
    }
}

private extension String {
    /// `"GREAT VALUE"` -> `"Great value"`. The band labels are shouted
    /// all-caps for the meter; in a running summary line that reads as anger.
    var capitalizedFirstWordOnly: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst().lowercased()
    }
}
