import SwiftUI

/// One selectable row in `VocabPickerView` — a small `Identifiable` wrapper
/// rather than a bare tuple, so `ForEach`/`List` can key on `\.id` without
/// relying on tuple-keypath support this build can't verify without Xcode.
private struct VocabEntry: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Edit sheet (PLAN.md §12 #42): every vocab-backed field is a **picker over
/// canonical values**, never free text, so an edit can't spawn an
/// inconsistent variant ("Ethiopia" vs "Etiopia") — roaster/farm get an
/// "Add new…" fallback that routes through #40's get-or-create; origin/roaster
/// country stay a closed picker (#36: countries never get-or-create).
///
/// Only fields the user actually touched are sent — comparing against the
/// value this sheet was opened with, not just "is the control non-empty", so
/// an untouched optional field never spuriously round-trips. A save with more
/// than one changed field goes through #41's batch `CoffeeStore.editFields`
/// (one HTTP request, no ordering race between e.g. a same-save `roaster` +
/// `roasterCountry` edit); a single-field save still uses `editField`.
struct CoffeeEditSheet: View {
    let coffee: Coffee
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    @State private var originCountryIDs: Set<Int>
    @State private var roasterCountryID: Int?
    @State private var roasterID: Int?
    @State private var newRoasterName = ""
    @State private var farmID: Int?
    @State private var newFarmName = ""
    @State private var profile: Profile?
    @State private var isDecaf: Bool
    @State private var altitudeMin: String
    @State private var altitudeMax: String
    @State private var weightGrams: String
    @State private var priceEur: String
    @State private var rating: Double
    @State private var hasRating: Bool
    @State private var roastedOn: Date
    @State private var hasRoastedOn: Bool

    private let originalOriginCountryIDs: Set<Int>
    private let originalRoasterCountryID: Int?
    private let originalRoasterID: Int?
    private let originalFarmID: Int?
    private let originalProfile: Profile?
    private let originalIsDecaf: Bool
    private let originalAltitudeMin: Int?
    private let originalAltitudeMax: Int?
    private let originalWeightG: Int?
    private let originalPriceEur: Double?
    private let originalRating: Double?
    private let originalRoastedOn: PlainDate?

    init(coffee: Coffee) {
        self.coffee = coffee

        originalOriginCountryIDs = Set(coffee.originCountryIds)
        originalRoasterCountryID = coffee.roasterCountryId
        originalRoasterID = coffee.roasterId
        originalFarmID = coffee.originFarmId
        originalProfile = coffee.profile
        originalIsDecaf = coffee.isDecaf
        originalAltitudeMin = coffee.altitudeMinM
        originalAltitudeMax = coffee.altitudeMaxM
        originalWeightG = coffee.weightG
        originalPriceEur = coffee.priceEur
        originalRating = coffee.rating
        originalRoastedOn = coffee.roastedOn

        _originCountryIDs = State(initialValue: Set(coffee.originCountryIds))
        _roasterCountryID = State(initialValue: coffee.roasterCountryId)
        _roasterID = State(initialValue: coffee.roasterId)
        _farmID = State(initialValue: coffee.originFarmId)
        _profile = State(initialValue: coffee.profile)
        _isDecaf = State(initialValue: coffee.isDecaf)
        _altitudeMin = State(initialValue: coffee.altitudeMinM.map(String.init) ?? "")
        _altitudeMax = State(initialValue: coffee.altitudeMaxM.map(String.init) ?? "")
        _weightGrams = State(initialValue: coffee.weightG.map(String.init) ?? "")
        _priceEur = State(initialValue: coffee.priceEur.map { String(format: "%.2f", $0) } ?? "")
        _rating = State(initialValue: coffee.rating ?? 3)
        _hasRating = State(initialValue: coffee.rating != nil)
        _roastedOn = State(initialValue: coffee.roastedOn?.utcMidnight ?? Date())
        _hasRoastedOn = State(initialValue: coffee.roastedOn != nil)
    }

    private var vocabulary: Vocabulary { store.index.vocabulary }

    var body: some View {
        NavigationStack {
            Form {
                originSection
                roasterSection
                processSection
                measurementsSection
                ratingAndDateSection
            }
            .navigationTitle("Edit coffee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Origin

    private var originSection: some View {
        Section("Origin") {
            NavigationLink {
                OriginCountryPickerView(
                    countries: vocabulary.countries.values.filter(\.isOrigin).sorted { $0.name < $1.name },
                    selection: $originCountryIDs
                )
            } label: {
                LabeledContent("Origin country", value: originSummary)
            }
        }
    }

    private var originSummary: String {
        let names = originCountryIDs.compactMap { vocabulary.countries[$0]?.name }.sorted()
        return names.isEmpty ? "Unknown" : names.joined(separator: ", ")
    }

    // MARK: - Roaster / farm

    private var roasterSection: some View {
        Section("Roaster") {
            NavigationLink {
                VocabPickerView(
                    title: "Roaster",
                    entries: vocabulary.roasters.values.sorted { $0.name < $1.name }.map { VocabEntry(id: $0.id, name: $0.name) },
                    selection: $roasterID,
                    newValue: $newRoasterName
                )
            } label: {
                LabeledContent("Roaster", value: roasterSummary)
            }
            NavigationLink {
                VocabPickerView(
                    title: "Roaster country",
                    entries: vocabulary.countries.values.filter(\.isRoaster).sorted { $0.name < $1.name }.map { VocabEntry(id: $0.id, name: $0.name) },
                    selection: $roasterCountryID,
                    newValue: nil
                )
            } label: {
                LabeledContent("Roaster country", value: roasterCountryID.flatMap { vocabulary.countries[$0]?.name } ?? "Unknown")
            }
            NavigationLink {
                VocabPickerView(
                    title: "Farm",
                    entries: vocabulary.farms.values.sorted { $0.name < $1.name }.map { VocabEntry(id: $0.id, name: $0.name) },
                    selection: $farmID,
                    newValue: $newFarmName
                )
            } label: {
                LabeledContent("Farm", value: farmSummary)
            }
        }
    }

    private var roasterSummary: String {
        let trimmed = newRoasterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return roasterID.flatMap { vocabulary.roasters[$0]?.name } ?? "Unknown"
    }

    private var farmSummary: String {
        let trimmed = newFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return farmID.flatMap { vocabulary.farms[$0]?.name } ?? "Unknown"
    }

    // MARK: - Process

    private var processSection: some View {
        Section("Process") {
            Picker("Process", selection: $profile) {
                Text("Unknown").tag(Profile?.none)
                ForEach(Profile.allCases) { p in
                    Text(p.displayName).tag(Optional(p))
                }
            }
            Toggle("Decaf", isOn: $isDecaf)
        }
    }

    // MARK: - Measurements

    private var measurementsSection: some View {
        Section("Measurements") {
            HStack {
                Text("Altitude (m)")
                Spacer()
                TextField("min", text: $altitudeMin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text("–")
                    .foregroundStyle(.secondary)
                TextField("max", text: $altitudeMax)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
            }
            HStack {
                Text("Weight (g)")
                Spacer()
                TextField("grams", text: $weightGrams)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            HStack {
                Text("Price (EUR)")
                Spacer()
                TextField("amount", text: $priceEur)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
        }
    }

    // MARK: - Rating & roast date

    private var ratingAndDateSection: some View {
        Section("Rating & roast date") {
            Toggle("Rating known", isOn: $hasRating)
            if hasRating {
                HStack {
                    Text("Rating")
                    Spacer()
                    Text(String(format: "%.1f", rating))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $rating, in: 0...5, step: 0.1)
            }

            Toggle("Roasted-on date known", isOn: $hasRoastedOn)
            if hasRoastedOn {
                DatePicker("Roasted on", selection: $roastedOn, displayedComponents: .date)
            }
        }
    }

    // MARK: - Save

    /// Builds the list of changed-field edits, then applies them via #41's
    /// `CoffeeStore` — a single-field save calls `editField`; a multi-field
    /// save calls the batch `editFields` (#41's atomicity fix for #42) so the
    /// backend resolves and applies them together in one request.
    private func save() {
        var edits: [CoffeeFieldEdit] = []

        if originCountryIDs != originalOriginCountryIDs {
            let names = originCountryIDs.compactMap { vocabulary.countries[$0]?.name }
            if !names.isEmpty {
                edits.append(CoffeeFieldEdit(field: "originCountry", value: names.joined(separator: ", ")))
            }
        }

        if roasterCountryID != originalRoasterCountryID,
           let id = roasterCountryID, let name = vocabulary.countries[id]?.name {
            edits.append(CoffeeFieldEdit(field: "roasterCountry", value: name))
        }

        let trimmedNewRoaster = newRoasterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNewRoaster.isEmpty {
            edits.append(CoffeeFieldEdit(field: "roaster", value: trimmedNewRoaster))
        } else if roasterID != originalRoasterID, let id = roasterID, let name = vocabulary.roasters[id]?.name {
            edits.append(CoffeeFieldEdit(field: "roaster", value: name))
        }

        let trimmedNewFarm = newFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNewFarm.isEmpty {
            edits.append(CoffeeFieldEdit(field: "farm", value: trimmedNewFarm))
        } else if farmID != originalFarmID, let id = farmID, let name = vocabulary.farms[id]?.name {
            edits.append(CoffeeFieldEdit(field: "farm", value: name))
        }

        if profile != originalProfile || isDecaf != originalIsDecaf {
            var text = profile?.displayName ?? ""
            if isDecaf { text += text.isEmpty ? "decaf" : " decaf" }
            edits.append(CoffeeFieldEdit(field: "profile", value: text))
        }

        if let minValue = Int(altitudeMin) {
            let maxValue = Int(altitudeMax) ?? minValue
            if Optional(minValue) != originalAltitudeMin || Optional(maxValue) != originalAltitudeMax {
                let text = minValue == maxValue ? "\(minValue) m" : "\(minValue)-\(maxValue) m"
                edits.append(CoffeeFieldEdit(field: "altitude", value: text))
            }
        }

        if let grams = Int(weightGrams), Optional(grams) != originalWeightG {
            edits.append(CoffeeFieldEdit(field: "weight", value: "\(grams)g"))
        }

        if let amount = Double(priceEur.replacingOccurrences(of: ",", with: ".")) {
            let changed = originalPriceEur.map { abs(amount - $0) > 0.005 } ?? true
            if changed {
                edits.append(CoffeeFieldEdit(field: "price", value: String(format: "%.2f EUR", amount)))
            }
        }

        if hasRating {
            let changed = originalRating.map { abs(rating - $0) > 0.001 } ?? true
            if changed {
                edits.append(CoffeeFieldEdit(field: "rating", value: String(format: "%.1f/5", rating)))
            }
        }

        if hasRoastedOn {
            let components = Calendar.utc.dateComponents([.year, .month, .day], from: roastedOn)
            if let y = components.year, let m = components.month, let d = components.day {
                let plain = PlainDate(year: y, month: m, day: d)
                if Optional(plain) != originalRoastedOn {
                    edits.append(CoffeeFieldEdit(field: "roastedOn", value: plain.isoString))
                }
            }
        }

        if edits.count > 1 {
            store.editFields(coffeeId: coffee.id, edits: edits)
        } else if let edit = edits.first {
            store.editField(coffeeId: coffee.id, field: edit.field, value: edit.value)
        }
        dismiss()
    }
}

/// A single-select searchable list over one vocab table (roaster/farm/roaster
/// country), with an optional "Add new…" fallback for open-ended vocab
/// (roaster/farm — #40's get-or-create). `newValue == nil` means a closed
/// vocab (countries, #36) — no add-new section renders at all.
private struct VocabPickerView: View {
    let title: String
    let entries: [VocabEntry]
    @Binding var selection: Int?
    var newValue: Binding<String>?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [VocabEntry] {
        guard !query.isEmpty else { return entries }
        let folded = query.foldedForSearch
        return entries.filter { $0.name.foldedForSearch.contains(folded) }
    }

    var body: some View {
        List {
            if let newValue {
                Section("Not listed?") {
                    HStack {
                        TextField("New \(title.lowercased()) name", text: newValue)
                        Button("Use") {
                            let trimmed = newValue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            selection = nil
                            dismiss()
                        }
                        .disabled(newValue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            Section {
                ForEach(filtered) { entry in
                    Button {
                        selection = entry.id
                        newValue?.wrappedValue = ""
                        dismiss()
                    } label: {
                        HStack {
                            Text(entry.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selection == entry.id {
                                Image(systemName: Symbols.pickerSelected)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The multi-select origin-country list — a blend just has more than one
/// selection here; there's no separate "is this a blend" toggle (#40/#36:
/// `isBlend` is derived server-side from how many ids resolve).
private struct OriginCountryPickerView: View {
    let countries: [Country]
    @Binding var selection: Set<Int>

    @State private var query = ""

    private var filtered: [Country] {
        guard !query.isEmpty else { return countries }
        let folded = query.foldedForSearch
        return countries.filter { $0.name.foldedForSearch.contains(folded) }
    }

    var body: some View {
        List(filtered) { country in
            Button {
                if selection.contains(country.id) {
                    selection.remove(country.id)
                } else {
                    selection.insert(country.id)
                }
            } label: {
                HStack {
                    Text(country.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(country.id) {
                        Image(systemName: Symbols.pickerSelected)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Origin country")
        .navigationBarTitleDisplayMode(.inline)
    }
}
