import PhotosUI
import SwiftUI

/// "Evaluate this coffee" (PLAN.md, backend #106, shell surface #136, this
/// screen #125): score a bag Radu doesn't own yet against his own rated
/// corpus. Same 3-step shape as the Add Coffee wizard — photo(s), paste the
/// shop listing text, see the result — reusing its exact upload path
/// (`CoffeeStore.uploadWizardPhotos`) rather than inventing a second one.
/// Nothing here is persisted: `CoffeeStore.evaluateCoffee` is ephemeral, like
/// `extractWizardDraft`, and the result is thrown away the moment this sheet
/// closes.
///
/// **#163's headline gate:** #106 forbids shipping the single "fit" number
/// until Radu has read real evaluations and agrees they read sensibly — a
/// human decision, not a lane's to make. `EvaluateCoffeeView.showHeadline`
/// is the one-word flip for that: `false` ships the whole screen today with
/// the headline hidden (the components and the low-confidence badge were
/// never gated, only the number), and flipping it to `true` is the entire
/// change once he says so.
struct EvaluateCoffeeView: View {
    /// #163: flip to `true` once Radu has read real evaluations (the sample
    /// in `status/backend.md`, or a fresh batch) and confirms the headline
    /// number reads sensibly. Until then this screen ships the components
    /// and the confidence badge only.
    static let showHeadline = false

    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case photos, text, result
    }

    @State private var step: Step = .photos
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Frames captured with the camera (#103), kept separate from
    /// `pickerItems` for the same reason the wizard keeps them separate: they
    /// are already `Data`, no `loadTransferable` round trip.
    @State private var capturedImages: [Data] = []
    @State private var showCamera = false
    @State private var imagesData: [Data] = []
    @State private var fullText = ""

    @State private var isBusy = false
    @State private var busyMessage = ""
    @State private var errorText: String?
    @State private var result: EvaluateResult?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .photos: photosStep
                case .text: textStep
                case .result: resultStep
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(step == .result ? "Done" : "Cancel") { dismiss() }
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
        case .photos: return "Evaluate a coffee"
        case .text: return "Bag text"
        case .result: return "Fit"
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    // MARK: - Step 1: photos

    private var photosStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: Symbols.evaluateEntry)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Score a bag you don't own yet")
                .font(.headline)
            Text("Photograph the shop listing or the bag itself — same as adding a coffee, but this one isn't saved to your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take photo", systemImage: Symbols.wizardCamera)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Label("Choose from library", systemImage: Symbols.wizardPhotos)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if selectedCount > 0 {
                    Text("\(selectedCount) photo\(selectedCount == 1 ? "" : "s") ready")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        capturedImages.append(data)
                    }
                }
                .ignoresSafeArea()
            }

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
            .disabled(selectedCount == 0 || isBusy)
        }
        .padding()
    }

    private var selectedCount: Int { pickerItems.count + capturedImages.count }

    private func loadImagesAndContinue() async {
        isBusy = true
        busyMessage = "Loading photos…"
        defer { isBusy = false }

        var datas: [Data] = capturedImages
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
            Text("Paste the listing text — title, description, price. The price is what makes the value half of the score possible.")
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
                Task { await evaluateAndShowResult() }
            } label: {
                if isBusy {
                    ProgressView(busyMessage)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Get fit score").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }

    private func evaluateAndShowResult() async {
        isBusy = true
        busyMessage = "Uploading photos…"
        defer { isBusy = false }

        do {
            let ids = try await store.uploadWizardPhotos(imagesData, fullText: fullText)
            busyMessage = "Scoring…"
            result = try await store.evaluateCoffee(photoIds: ids)
            step = .result
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Step 3: result

    @ViewBuilder
    private var resultStep: some View {
        if let result {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    EvaluateFactsRow(fields: result.fields, vocabulary: store.index.vocabulary)
                    EvaluateHeadlineBlock(evaluation: result.evaluation)
                    EvaluateComponentsRow(components: result.evaluation.components)
                    if let banner = EvaluatePriceBanner.message(for: result.fields, components: result.evaluation.components) {
                        EvaluatePriceBanner(text: banner) { step = .text }
                    }
                    Button("Evaluate another coffee") {
                        resetForAnotherEvaluation()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
        } else {
            ProgressView()
        }
    }

    private func resetForAnotherEvaluation() {
        pickerItems = []
        capturedImages = []
        imagesData = []
        fullText = ""
        result = nil
        step = .photos
    }
}
