import SwiftUI
import UIKit

/// The Brew lab logging sheet (PLAN.md §14, backlog #157) — the whole point of
/// the feature: "what did I actually brew this with, and which one won."
///
/// Four sections in fixed order — recipe → device → grind → temp — but two
/// shapes, because the catalogues are shaped differently:
/// - **recipe + device** are list rows (`[✓] label … 🏆`), since they carry a
///   name and, for recipes, a whole spec line;
/// - **grind + temp** are chip grids over `WrapLayout`, because 21 Comandante
///   click values and ~16 temperatures rendered as rows would be a 37-row
///   scroll to find one number. Tap = tried, long-press = best.
///
/// Every tap is optimistic: `CoffeeStore.setBrewState` mutates the in-memory
/// index and enqueues the write, so the sheet never shows a spinner and works
/// offline. Failures surface through `store.brewErrorText` as a toast, the
/// same pattern the edit sheet uses for `editErrorText`.
struct BrewLabSheet: View {
    let coffeeId: String

    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    /// Which "Add <kind>…" affordance is currently expanded, if any — only one
    /// at a time, so the sheet never grows two inline editors.
    @State private var addingKind: BrewKind?
    @State private var newDeviceLabel: String = ""
    @State private var newGrindClicks: Int = 24
    @State private var newTempC: Int = 94
    @State private var showRecipeForm = false
    @State private var pendingUntickWinner: BrewOption?
    @State private var isSaving = false

    /// Read through the store every time rather than capturing a `Coffee`:
    /// `setBrewState` republishes a whole new index, and a captured value
    /// would show stale ticks after the first tap.
    private var coffee: Coffee? { store.index.coffee(id: coffeeId) }

    var body: some View {
        NavigationStack {
            Group {
                if let coffee {
                    List {
                        rowSection(.recipe, coffee: coffee)
                        rowSection(.device, coffee: coffee)
                        chipSection(.grind, coffee: coffee)
                        chipSection(.temp, coffee: coffee)
                    }
                    .listStyle(.insetGrouped)
                } else {
                    // The coffee left the index mid-sheet (a sync dropped it).
                    ContentUnavailableView("Coffee unavailable", systemImage: Symbols.emptyCup)
                }
            }
            .navigationTitle("Brew lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRecipeForm) {
                RecipeFormSheet { label, detail, spec in
                    await addRecipe(label: label, detail: detail, spec: spec)
                }
            }
            .confirmationDialog(
                "Untick the winner?",
                isPresented: Binding(
                    get: { pendingUntickWinner != nil },
                    set: { if !$0 { pendingUntickWinner = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Untick and clear winner", role: .destructive) {
                    if let option = pendingUntickWinner {
                        set(option, to: .untried)
                    }
                    pendingUntickWinner = nil
                }
                Button("Keep it", role: .cancel) { pendingUntickWinner = nil }
            } message: {
                Text("\(pendingUntickWinner?.label ?? "This") is this coffee's best \(pendingUntickWinner?.kind.displayName.lowercased() ?? "option"). Unticking it clears the trophy too.")
            }
            .overlay(alignment: .bottom) { errorToast }
        }
    }

    // MARK: - List sections (recipe, device)

    @ViewBuilder
    private func rowSection(_ kind: BrewKind, coffee: Coffee) -> some View {
        Section {
            ForEach(options(of: kind, coffee: coffee)) { option in
                BrewOptionRow(
                    option: option,
                    state: store.index.brewState(for: coffee, option: option),
                    onToggleTried: { toggleTried(option, coffee: coffee) },
                    onMarkBest: { set(option, to: .best) }
                )
            }
            addRow(kind)
        } header: {
            sectionHeader(kind, coffee: coffee)
        }
    }

    // MARK: - Chip sections (grind, temp)

    @ViewBuilder
    private func chipSection(_ kind: BrewKind, coffee: Coffee) -> some View {
        Section {
            let all = options(of: kind, coffee: coffee)
            if all.isEmpty {
                Text("Nothing in this catalogue yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.neutral700)
            } else {
                WrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(all) { option in
                        BrewValueChip(
                            option: option,
                            state: store.index.brewState(for: coffee, option: option),
                            onTap: { toggleTried(option, coffee: coffee) },
                            onLongPress: { set(option, to: .best) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            addRow(kind)
        } header: {
            sectionHeader(kind, coffee: coffee)
        }
    }

    // MARK: - Shared section pieces

    /// Archived options are hidden unless *this* coffee tried one — an archived
    /// grind you actually used is still part of this coffee's history.
    private func options(of kind: BrewKind, coffee: Coffee) -> [BrewOption] {
        let tried = Set(coffee.triedBrewOptionIds)
        return store.index.vocabulary
            .brewOptions(of: kind, includeArchived: true)
            .filter { !$0.archived || tried.contains($0.id) }
    }

    private func sectionHeader(_ kind: BrewKind, coffee: Coffee) -> some View {
        let triedCount = store.index.triedBrewOptions(for: coffee, kind: kind).count
        let suffix = triedCount > 0 ? " · \(triedCount) tried" : ""
        return Text(kind.sectionTitle + suffix)
    }

    @ViewBuilder
    private func addRow(_ kind: BrewKind) -> some View {
        if addingKind == kind {
            switch kind {
            case .device:
                HStack {
                    TextField("Device name", text: $newDeviceLabel)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { Task { await commitAdd(kind) } }
                    Button("Add") { Task { await commitAdd(kind) } }
                        .disabled(newDeviceLabel.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            case .grind:
                wheelAdd(kind, selection: $newGrindClicks, range: 1...60) { "\($0) clicks" }
            case .temp:
                wheelAdd(kind, selection: $newTempC, range: 60...100) { "\($0) °C" }
            case .recipe:
                EmptyView()
            }
        } else {
            Button {
                if kind == .recipe {
                    showRecipeForm = true
                } else {
                    addingKind = kind
                }
            } label: {
                Label("Add \(kind.displayName.lowercased())…", systemImage: Symbols.plus)
                    .font(.system(size: 13))
            }
            .frame(minHeight: 44)
        }
    }

    private func wheelAdd(
        _ kind: BrewKind,
        selection: Binding<Int>,
        range: ClosedRange<Int>,
        label: @escaping (Int) -> String
    ) -> some View {
        VStack(spacing: 8) {
            Picker(kind.displayName, selection: selection) {
                ForEach(Array(range), id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            HStack {
                Button("Cancel") { addingKind = nil }
                Spacer()
                Button("Add") { Task { await commitAdd(kind) } }
                    .disabled(isSaving)
            }
            .font(.system(size: 13, weight: Theme.Weight.semibold))
        }
    }

    @ViewBuilder
    private var errorToast: some View {
        if let message = store.brewErrorText {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.pill).fill(Color.black.opacity(0.82)))
                .padding(.bottom, 20)
                .transition(.opacity)
                .onTapGesture { store.brewErrorText = nil }
        }
    }

    // MARK: - Mutations

    /// Leading checkbox: untried ↔ tried. Unticking the current winner asks
    /// first — losing a trophy to a stray tap on a checklist is the one
    /// destructive thing here.
    private func toggleTried(_ option: BrewOption, coffee: Coffee) {
        switch store.index.brewState(for: coffee, option: option) {
        case .untried: set(option, to: .tried)
        case .tried: set(option, to: .untried)
        case .best: pendingUntickWinner = option
        }
    }

    private func set(_ option: BrewOption, to state: BrewTrialState) {
        // Optimistic and fire-and-forget by design (PLAN.md §14) — the store
        // republishes the index, so the row restyles on the next render and
        // the previous winner in this kind loses its trophy server-side and
        // in memory both.
        withAnimation(.easeInOut(duration: 0.18)) {
            store.setBrewState(coffeeId: coffeeId, optionId: option.id, state: state)
        }
    }

    private func commitAdd(_ kind: BrewKind) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let option: BrewOption
            switch kind {
            case .device:
                let label = newDeviceLabel.trimmingCharacters(in: .whitespaces)
                guard !label.isEmpty else { return }
                option = try await store.createBrewOption(kind: .device, label: label)
            case .grind:
                option = try await store.createBrewOption(
                    kind: .grind, label: "\(newGrindClicks)", valueNum: Double(newGrindClicks)
                )
            case .temp:
                option = try await store.createBrewOption(
                    kind: .temp, label: "\(newTempC)", valueNum: Double(newTempC)
                )
            case .recipe:
                return
            }
            // A new option appears already ticked — you only add one because
            // you just brewed with it. Duplicates resolve to the existing row
            // server-side, so this is also the "tick the one I meant" path.
            set(option, to: .tried)
            newDeviceLabel = ""
            addingKind = nil
        } catch {
            // `createBrewOption` already routed the message to brewErrorText.
        }
    }

    private func addRecipe(label: String, detail: String?, spec: BrewRecipeSpec) async {
        do {
            let option = try await store.createBrewOption(
                kind: .recipe, label: label, detail: detail, recipe: spec
            )
            set(option, to: .tried)
        } catch {
            // Surfaced via brewErrorText.
        }
    }
}

// MARK: - Rows and chips

/// One recipe/device row: leading checkbox (tried), label stack, trailing
/// trophy (best). Both are real 44pt targets; the whole row is not tappable on
/// purpose, so the two meanings stay distinguishable.
private struct BrewOptionRow: View {
    let option: BrewOption
    let state: BrewTrialState
    let onToggleTried: () -> Void
    let onMarkBest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleTried) {
                Image(systemName: state == .untried ? Symbols.checkboxEmpty : Symbols.checkboxChecked)
                    .font(.system(size: 20))
                    .foregroundStyle(state == .untried ? Theme.Colors.neutral300 : Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state == .untried ? "Mark \(option.label) tried" : "Mark \(option.label) untried")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.label)
                        .font(.system(size: 14, weight: state == .untried ? .regular : Theme.Weight.semibold))
                        .foregroundStyle(state == .untried ? Theme.Colors.neutral700 : Theme.Colors.text)
                    if option.archived {
                        Text("archived")
                            .font(.system(size: 9, weight: Theme.Weight.semibold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                if let recipe = option.recipe {
                    Text(recipe.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.neutral700)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if let detail = option.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.neutral700)
                        .lineLimit(2)
                }
            }
            .opacity(option.archived ? 0.55 : 1)

            Spacer(minLength: 0)

            Button(action: onMarkBest) {
                Image(systemName: state == .best ? Symbols.trophyFill : Symbols.trophy)
                    .font(.system(size: 15))
                    .foregroundStyle(state == .best ? Theme.Colors.accent : Theme.Colors.neutral300)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(option.label) best")
        }
        .padding(.vertical, 2)
    }
}

/// One grind/temp value as a chip. Tap = tried, long-press = best (with a
/// haptic, since a long-press has no other feedback), matching the spec's
/// "the value IS the identity" framing for these two catalogues.
private struct BrewValueChip: View {
    let option: BrewOption
    let state: BrewTrialState
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var fill: Color {
        switch state {
        case .untried: return .clear
        case .tried: return Theme.Colors.neutral300.opacity(0.45)
        case .best: return Theme.Colors.accent
        }
    }

    private var foreground: Color {
        switch state {
        case .untried: return Theme.Colors.neutral700
        case .tried: return Theme.Colors.text
        case .best: return Theme.Colors.onAccent
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(option.chipLabel)
                .font(.system(size: 13, weight: state == .untried ? .regular : Theme.Weight.semibold))
            if state == .best {
                Image(systemName: Symbols.trophyFill).font(.system(size: 10))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(minWidth: 44, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.pill).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.pill)
                .strokeBorder(state == .best ? Theme.Colors.accent : Theme.Colors.neutral300, lineWidth: 1)
        )
        .opacity(option.archived ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        }
        .accessibilityLabel(option.chipLabel)
        .accessibilityValue(state.accessibilityDescription)
    }
}

// MARK: - Small shared vocabulary

extension BrewKind {
    /// Section headers carry the unit, because "24" and "94" are meaningless
    /// on their own — the grind number is Comandante clicks, the temp is °C.
    var sectionTitle: String {
        switch self {
        case .recipe: return "Recipe"
        case .device: return "Device"
        case .grind: return "Grind · Comandante clicks"
        case .temp: return "Temperature"
        }
    }
}

extension BrewOption {
    /// A grind chip reads "24", a temperature chip "94°" — the catalogue label
    /// is already just the number for both kinds, so this only adds the unit
    /// where one helps.
    var chipLabel: String {
        kind == .temp ? label + "°" : label
    }
}

extension BrewTrialState {
    var accessibilityDescription: String {
        switch self {
        case .untried: return "not tried"
        case .tried: return "tried"
        case .best: return "best"
        }
    }
}
