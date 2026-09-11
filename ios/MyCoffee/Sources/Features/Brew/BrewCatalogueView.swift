import SwiftUI

/// The Brew lab catalogues, managed in one place (PLAN.md §14, backlog #157).
/// Reached from Settings, because this is library-wide maintenance — the
/// per-coffee sheet is where you *log*, this is where you fix a typo or retire
/// a device you sold.
///
/// **No delete, by design.** Options are referenced by every coffee that ever
/// tried them, so removing one would rewrite history; archiving hides it from
/// the pickers while leaving the coffees that used it intact (`BrewLabSheet`
/// still shows an archived option on a coffee that tried it).
///
/// Editing differs by kind, and that asymmetry is deliberate: a device or a
/// recipe has a *name* that can be wrong, but for grind and temperature the
/// value **is** the identity — "24 clicks" renamed to "26" would silently
/// rewrite what every coffee using it means. Those two archive-and-re-add
/// instead.
struct BrewCatalogueView: View {
    @EnvironmentObject private var store: CoffeeStore

    @State private var kind: BrewKind = .recipe
    @State private var renaming: BrewOption?
    @State private var renameText: String = ""
    @State private var editingRecipe: BrewOption?
    @State private var showAddRecipe = false
    @State private var newLabel: String = ""
    @State private var showAddDevice = false

    private var options: [BrewOption] {
        store.index.vocabulary.brewOptions(of: kind, includeArchived: true)
    }

    var body: some View {
        List {
            Section {
                Picker("Catalogue", selection: $kind) {
                    ForEach(BrewKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section {
                if options.isEmpty {
                    Text("Nothing here yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.neutral700)
                } else {
                    ForEach(options) { option in
                        row(option)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(option.archived ? "Unarchive" : "Archive") {
                                    Task { await setArchived(option, !option.archived) }
                                }
                                .tint(option.archived ? Theme.Colors.accent : .orange)

                                if kind == .device {
                                    Button("Edit") {
                                        renameText = option.label
                                        renaming = option
                                    }
                                    .tint(Theme.Colors.accent700)
                                } else if kind == .recipe {
                                    Button("Edit") { editingRecipe = option }
                                        .tint(Theme.Colors.accent700)
                                }
                            }
                    }
                    // Reorder controls only appear in edit mode, and the
                    // EditButton is only offered for the two ordered
                    // catalogues — so this never fires for grind/temp.
                    .onMove { source, destination in
                        guard isReorderable else { return }
                        move(from: source, to: destination)
                    }
                }
            } header: {
                Text(kind.displayName)
            } footer: {
                Text(footerText)
            }

            if kind == .recipe || kind == .device {
                Section {
                    Button {
                        if kind == .recipe {
                            showAddRecipe = true
                        } else {
                            newLabel = ""
                            showAddDevice = true
                        }
                    } label: {
                        Label("Add \(kind.displayName.lowercased())…", systemImage: Symbols.plus)
                    }
                }
            }
        }
        .navigationTitle("Brew catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isReorderable {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let option = renaming { Task { await rename(option) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .sheet(isPresented: $showAddRecipe) {
            RecipeFormSheet { label, detail, spec in
                _ = try? await store.createBrewOption(
                    kind: .recipe, label: label, detail: detail, recipe: spec
                )
            }
        }
        .sheet(item: $editingRecipe) { option in
            RecipeFormSheet(existing: option) { label, detail, spec in
                _ = try? await store.updateBrewOption(
                    id: option.id,
                    patch: BrewOptionPatch(label: label, detail: detail, recipe: spec)
                )
            }
        }
        .alert("New device", isPresented: $showAddDevice) {
            TextField("Name", text: $newLabel)
            Button("Add") {
                let label = newLabel.trimmingCharacters(in: .whitespaces)
                guard !label.isEmpty else { return }
                Task { _ = try? await store.createBrewOption(kind: .device, label: label) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let message = store.brewErrorText {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.pill).fill(Color.black.opacity(0.82)))
                    .padding(.bottom, 20)
                    .onTapGesture { store.brewErrorText = nil }
            }
        }
    }

    /// Only the two named catalogues carry a meaningful order. Grind and temp
    /// sort by their own numeric value — dragging "94 °C" above "88 °C" would
    /// be a lie the next rebuild undoes.
    private var isReorderable: Bool { kind == .recipe || kind == .device }

    private var footerText: String {
        switch kind {
        case .recipe, .device:
            return "Swipe a row to edit or archive it. Drag to reorder. Archived options stay on the coffees that used them."
        case .grind, .temp:
            return "The value is the name here, so there is nothing to rename — archive one and add the right value instead. Add new values from a coffee's Brew lab."
        }
    }

    private func row(_ option: BrewOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(option.chipLabel)
                    .font(.system(size: 14, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.text)
                if option.archived {
                    Text("archived")
                        .font(.system(size: 9, weight: Theme.Weight.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Colors.neutral700)
                }
                Spacer(minLength: 0)
                Text(winRateText(option))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
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
    }

    /// "won 7 of 12" — the same shape #158's Insights card will use, shown
    /// here because the catalogue is exactly where you decide what to retire.
    private func winRateText(_ option: BrewOption) -> String {
        guard let stats = store.index.brewWinRates(kind: option.kind).first(where: { $0.option.id == option.id }),
              stats.tried > 0
        else { return "" }
        return "won \(stats.won) of \(stats.tried)"
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = options
        reordered.move(fromOffsets: source, toOffset: destination)
        Task {
            for (position, option) in reordered.enumerated() where option.sortOrder != position {
                _ = try? await store.updateBrewOption(id: option.id, patch: BrewOptionPatch(sortOrder: position))
            }
        }
    }

    private func rename(_ option: BrewOption) async {
        let label = renameText.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label != option.label else { return }
        _ = try? await store.updateBrewOption(id: option.id, patch: BrewOptionPatch(label: label))
    }

    private func setArchived(_ option: BrewOption, _ archived: Bool) async {
        _ = try? await store.updateBrewOption(id: option.id, patch: BrewOptionPatch(archived: archived))
    }
}
