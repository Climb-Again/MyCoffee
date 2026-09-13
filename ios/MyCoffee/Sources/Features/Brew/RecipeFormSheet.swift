import SwiftUI

/// Builds a `BrewRecipeSpec` (PLAN.md §14, backlog #157). Radu's recipes are
/// structured, not free text — dose, pours, ml per pour, total water, grind
/// clicks, water temp — so this is a form over those six numbers plus a name
/// and an optional note, not a text box.
///
/// Two behaviours worth knowing:
/// - **total water is prefilled** from `pours × mlPerPour` and stays in sync
///   until you type over it; after that it is yours and stops tracking. Even
///   pours are the common case, so typing the product every time would be
///   busywork — but uneven pours (the reason `mlPerPour` is optional at all)
///   need the total to be independent.
/// - **the ratio footer is live** ("1:15.0"), because the ratio is the number
///   a brewer actually reasons about, and it is derived, not entered.
///
/// Doubles as the edit form: pass `existing` to prefill, and the caller sends
/// a `PATCH` instead of a `POST`.
struct RecipeFormSheet: View {
    /// Prefill for an edit; `nil` creates a new recipe.
    var existing: BrewOption? = nil
    /// Called on Save. Throwing/failure handling belongs to the caller (which
    /// owns the store), so this is a plain async closure.
    let onSave: (String, String?, BrewRecipeSpec) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""
    @State private var doseText: String = ""
    @State private var pours: Int = 5
    @State private var mlPerPourText: String = ""
    @State private var totalWaterText: String = ""
    @State private var grindClicks: Int = 24
    @State private var waterTempC: Int = 92
    @State private var note: String = ""
    /// Once the total is typed over, it stops following `pours × mlPerPour`.
    @State private var totalWaterEdited = false
    @State private var isSaving = false

    private var dose: Double? {
        Double(doseText.replacingOccurrences(of: ",", with: "."))
    }
    private var mlPerPour: Int? { Int(mlPerPourText) }
    private var totalWater: Int? { Int(totalWaterText) }

    private var derivedTotal: Int? {
        guard let mlPerPour, pours > 0 else { return nil }
        return mlPerPour * pours
    }

    private var spec: BrewRecipeSpec? {
        guard let dose, dose > 0, let totalWater, totalWater > 0, pours > 0 else { return nil }
        return BrewRecipeSpec(
            doseG: dose,
            pours: pours,
            mlPerPour: mlPerPour,
            totalWaterMl: totalWater,
            grindClicks: grindClicks,
            waterTempC: waterTempC
        )
    }

    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedLabel.isEmpty && spec != nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. 4:6 Hoffmann", text: $label)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    LabeledContent("Coffee") {
                        HStack(spacing: 4) {
                            TextField("20", text: $doseText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70)
                            Text("g").foregroundStyle(Theme.Colors.neutral700)
                        }
                    }
                    Stepper("Pours: \(pours)", value: $pours, in: 1...12)
                        .onChange(of: pours) { _, _ in syncTotal() }
                    LabeledContent("Per pour") {
                        HStack(spacing: 4) {
                            TextField("optional", text: $mlPerPourText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70)
                                .onChange(of: mlPerPourText) { _, _ in syncTotal() }
                            Text("ml").foregroundStyle(Theme.Colors.neutral700)
                        }
                    }
                    LabeledContent("Total water") {
                        HStack(spacing: 4) {
                            TextField("300", text: $totalWaterText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70)
                                .onChange(of: totalWaterText) { _, new in
                                    // Only a *manual* divergence detaches it —
                                    // `syncTotal`'s own writes must not.
                                    if new != derivedTotal.map(String.init) { totalWaterEdited = true }
                                }
                            Text("ml").foregroundStyle(Theme.Colors.neutral700)
                        }
                    }
                } header: {
                    Text("Dose and water")
                } footer: {
                    if let spec {
                        Text("Ratio 1:\(String(format: "%.1f", spec.ratio))")
                            .font(.system(size: 12, weight: Theme.Weight.semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    } else {
                        Text("Coffee weight and total water are required.")
                    }
                }

                Section("Grind") {
                    Picker("Comandante clicks", selection: $grindClicks) {
                        ForEach(1...60, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                }

                Section("Water temperature") {
                    Picker("°C", selection: $waterTempC) {
                        ForEach(60...100, id: \.self) { Text("\($0) °C").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                }

                Section("Note") {
                    TextField("optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(existing == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let spec else { return }
                        isSaving = true
                        Task {
                            let trimmedNote = note.trimmingCharacters(in: .whitespaces)
                            await onSave(trimmedLabel, trimmedNote.isEmpty ? nil : trimmedNote, spec)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func syncTotal() {
        guard !totalWaterEdited, let derivedTotal else { return }
        totalWaterText = String(derivedTotal)
    }

    private func prefill() {
        guard let existing, let recipe = existing.recipe, label.isEmpty else { return }
        label = existing.label
        note = existing.detail ?? ""
        doseText = recipe.doseG.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", recipe.doseG)
            : String(format: "%.1f", recipe.doseG)
        pours = recipe.pours
        mlPerPourText = recipe.mlPerPour.map(String.init) ?? ""
        totalWaterText = String(recipe.totalWaterMl)
        // An existing recipe's total is already authoritative — never let
        // `syncTotal` rewrite a saved uneven-pour total on first appearance.
        totalWaterEdited = true
        grindClicks = recipe.grindClicks
        waterTempC = recipe.waterTempC
    }
}
