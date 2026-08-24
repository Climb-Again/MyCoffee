import PhotosUI
import SwiftUI

/// The Add Coffee wizard (PLAN.md §6.8, #77): pick photos, paste the bag's
/// printed text, then confirm/edit the light-extraction draft before it's
/// saved as a brand-new, `locked=true`/human-decided coffee (#75/#76). Reached
/// from a floating "+" over the tab bar (`RootTabView`), not a fourth tab —
/// the "three tabs" decision (`CLAUDE.md`) stays intact.
struct AddCoffeeWizardView: View {
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case photos, text, confirm
    }

    @State private var step: Step = .photos
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var imagesData: [Data] = []
    @State private var fullText = ""
    @State private var photoIds: [String] = []
    @State private var draftFields: [DraftField] = []
    @State private var editedValues: [String: String] = [:]

    @State private var isBusy = false
    @State private var busyMessage = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .photos: photosStep
                case .text: textStep
                case .confirm: confirmStep
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
        }
        .presentationDetents([.large])
        .alert("Couldn't continue", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var title: String {
        switch step {
        case .photos: return "Add coffee"
        case .text: return "Bag text"
        case .confirm: return "Confirm"
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    // MARK: - Step 1: photos

    private var photosStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: Symbols.wizardPhotos)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Start with the bag's front and back")
                .font(.headline)
            Text("Add every photo that shows printed text — roaster, origin, process, weight, price. You'll paste the text next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                Label(pickerItems.isEmpty ? "Choose photos" : "\(pickerItems.count) photo\(pickerItems.count == 1 ? "" : "s") selected — change", systemImage: Symbols.wizardPhotos)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                Task { await loadImagesAndContinue() }
            } label: {
                if isBusy {
                    ProgressView(busyMessage)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Next").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pickerItems.isEmpty || isBusy)
        }
        .padding()
    }

    private func loadImagesAndContinue() async {
        isBusy = true
        busyMessage = "Loading photos…"
        defer { isBusy = false }

        var datas: [Data] = []
        for item in pickerItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                datas.append(data)
            }
        }
        guard !datas.isEmpty else {
            errorText = "Couldn't load the selected photos. Try again."
            return
        }
        imagesData = datas
        step = .text
    }

    // MARK: - Step 2: bag text

    private var textStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste everything printed on the bag — title, description, any caption text. The more you paste, the better the read.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $fullText)
                    .frame(minHeight: 240)
                if fullText.isEmpty {
                    Text("Paste text here…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))

            Button {
                Task { await extractAndContinue() }
            } label: {
                if isBusy {
                    ProgressView(busyMessage)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Extract").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }

    private func extractAndContinue() async {
        isBusy = true
        busyMessage = "Uploading photos…"
        defer { isBusy = false }

        do {
            let ids = try await store.uploadWizardPhotos(imagesData, fullText: fullText)
            photoIds = ids
            busyMessage = "Reading the bag…"
            let draft = try await store.extractWizardDraft(photoIds: ids)
            let fields = draft.fields.values.filter { !$0.isAbsent }
            draftFields = fields
            for field in fields {
                editedValues[field.field] = field.value ?? field.candidates.first?.value ?? ""
            }
            step = .confirm
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Step 3: confirm

    /// Client field names in a fixed display order (mirrors `CoffeeEditSheet`'s
    /// section order) — `EDIT_FIELD_TO_CLIENT`'s full set, backend-owned
    /// (`backend/src/lib/resolveField.js`).
    private static let fieldOrder = [
        "originCountry", "roasterCountry", "roaster", "farm", "profile",
        "altitude", "weight", "price", "rating", "roastedOn",
    ]

    private var orderedDraftFields: [DraftField] {
        let byField = Dictionary(uniqueKeysWithValues: draftFields.map { ($0.field, $0) })
        return Self.fieldOrder.compactMap { byField[$0] }
    }

    private var confirmStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if draftFields.isEmpty {
                        Text("Nothing came back from the extraction — you can still save with the photos alone, then fill in details from the coffee's edit sheet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                    } else {
                        ForEach(orderedDraftFields) { field in
                            DraftFieldRow(
                                field: field,
                                label: fieldLabel(field.field),
                                symbol: fieldSymbol(field.field),
                                value: valueBinding(for: field.field)
                            )
                        }
                    }
                }
                .padding()
            }

            Divider()

            Button {
                Task { await save() }
            } label: {
                if isBusy {
                    ProgressView(busyMessage)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save coffee").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
            .padding()
        }
    }

    private func valueBinding(for field: String) -> Binding<String> {
        Binding(
            get: { editedValues[field] ?? "" },
            set: { editedValues[field] = $0 }
        )
    }

    /// Reuses `ReviewField`'s label/symbol for the eight fields the review
    /// queue (#27) already names — `rating`/`roastedOn` only exist on the
    /// generic edit endpoint (#40), so they're not in that enum.
    private func fieldLabel(_ field: String) -> String {
        if let reviewField = ReviewField(rawValue: field) { return reviewField.label }
        switch field {
        case "rating": return "Rating"
        case "roastedOn": return "Roasted on"
        default: return field
        }
    }

    private func fieldSymbol(_ field: String) -> String {
        if let reviewField = ReviewField(rawValue: field) { return reviewField.symbol }
        switch field {
        case "rating": return Symbols.starFill
        case "roastedOn": return Symbols.calendar
        default: return Symbols.processUnknown
        }
    }

    private func save() async {
        isBusy = true
        busyMessage = "Saving…"
        defer { isBusy = false }

        let edits: [CoffeeFieldEdit] = draftFields.compactMap { field in
            let value = (editedValues[field.field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return CoffeeFieldEdit(field: field.field, value: value)
        }

        do {
            _ = try await store.createWizardCoffee(photoIds: photoIds, fields: edits)
            store.selectedTab = .coffees
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// One confirmable field on the wizard's confirm screen: label + a
/// confidence mark, tappable value chips (the extracted value first, then any
/// other candidates), and a free-text fallback — the same chip-then-edit
/// language `ReviewCardView` (#27) uses for the review queue, adapted to
/// `DraftField`'s unconfirmed-draft shape (no task id, no accept/dismiss
/// actions — the whole draft saves or doesn't, together, in `#77`'s single
/// "Save coffee" button).
private struct DraftFieldRow: View {
    let field: DraftField
    let label: String
    let symbol: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                confidenceBadge
            }
            .foregroundStyle(.secondary)

            if chipValues.count > 1 {
                WrapLayout() {
                    ForEach(chipValues, id: \.self) { candidate in
                        Button {
                            value = candidate
                        } label: {
                            Text(candidate)
                                .font(.subheadline.weight(value == candidate ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    value == candidate ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Enter \(label.lowercased())", text: $value)
                .textFieldStyle(.roundedBorder)

            if let evidence = field.evidence, !evidence.isEmpty {
                Text(evidence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    /// The extracted value first (if any), then any other candidates not
    /// already equal to it — de-duplicated so a value that's also the top
    /// candidate doesn't render as two identical chips.
    private var chipValues: [String] {
        var seen = Set<String>()
        var values: [String] = []
        if let value = field.value {
            values.append(value)
            seen.insert(value)
        }
        for candidate in field.candidates where !seen.contains(candidate.value) {
            values.append(candidate.value)
            seen.insert(candidate.value)
        }
        return values
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        switch field.decision {
        case "accepted":
            Image(systemName: Symbols.reviewAccept).foregroundStyle(.green)
        case "split":
            Image(systemName: Symbols.needsReview).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}
