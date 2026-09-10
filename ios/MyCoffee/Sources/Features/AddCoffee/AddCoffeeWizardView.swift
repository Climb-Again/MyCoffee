import PhotosUI
import SwiftUI

/// The Add Coffee wizard (PLAN.md §6.8, #77, submit-and-return per #131):
/// pick photos, paste the bag's printed text, then save immediately — no
/// confirm screen. The coffee exists the instant `quickCreateCoffee` returns
/// (`reviewState == "unextracted"`); the backend's background extraction pass
/// fills in every field via the next normal sync, and anything it can't
/// resolve on its own lands in the existing review queue same as always, so
/// "confirm" moves from *before* save to the review queue *after*. Reached
/// from a floating "+" over the tab bar (`RootTabView`), not a fourth tab —
/// the "three tabs" decision (`CLAUDE.md`) stays intact.
struct AddCoffeeWizardView: View {
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case photos, text
    }

    @State private var step: Step = .photos
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Frames captured with the camera (#103). Kept separate from
    /// `pickerItems` because they are already `Data` — there is no
    /// `loadTransferable` round trip — and both sources merge in
    /// `loadImagesAndContinue`.
    @State private var capturedImages: [Data] = []
    @State private var showCamera = false
    @State private var imagesData: [Data] = []
    @State private var fullText = ""

    @State private var isBusy = false
    @State private var busyMessage = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .photos: photosStep
                case .text: textStep
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

            // #103: camera OR library, chosen up front. The camera button is
            // hidden rather than disabled where there is no camera (Simulator),
            // so the library is simply the only route instead of a dead button.
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
                    // 0.85 JPEG: camera frames come off the sensor far larger
                    // than a library asset, and the 50 MB app+data budget
                    // (CLAUDE.md §12) applies to what we cache after upload.
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

    /// Photos ready to upload, from either source.
    private var selectedCount: Int { pickerItems.count + capturedImages.count }

    private func loadImagesAndContinue() async {
        isBusy = true
        busyMessage = "Loading photos…"
        defer { isBusy = false }

        // Camera frames first, in capture order, then anything picked from the
        // library — both end up as JPEG `Data` on the same upload path.
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
                Task { await uploadAndSave() }
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
        }
        .padding()
    }

    /// Uploads the photos + pasted text, then creates the coffee instantly
    /// (`quickCreateCoffee`, #118/#130/#131) and returns to the listing —
    /// there is no confirm step to wait through: the coffee shows up right
    /// away with `reviewState == "unextracted"` and an "extracting…" badge
    /// (`CoffeeRowView`/`CoffeeDetailView`) until the backend's background
    /// pass fills it in.
    private func uploadAndSave() async {
        isBusy = true
        busyMessage = "Uploading photos…"
        defer { isBusy = false }

        do {
            let ids = try await store.uploadWizardPhotos(imagesData, fullText: fullText)
            busyMessage = "Saving…"
            _ = try await store.quickCreateCoffee(photoIds: ids)
            store.selectedTab = .coffees
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
