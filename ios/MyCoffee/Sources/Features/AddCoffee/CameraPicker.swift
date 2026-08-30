import SwiftUI
import UIKit

/// A camera capture sheet for the Add Coffee wizard (#103).
///
/// SwiftUI has no native camera view on the iOS 17 deployment target, so this
/// wraps `UIImagePickerController`. Deliberately the small wrapper rather than
/// a full `AVCapture` session: the wizard needs one still frame at a time, and
/// `UIImagePickerController` brings the shutter, retake and flash affordances
/// for free.
///
/// # Two things that make this crash or look broken if missed
///
/// 1. `Info.plist` **must** carry `NSCameraUsageDescription`. iOS terminates
///    the app the instant it touches the camera without it — not a permission
///    denial, a hard kill. (The wizard's `PhotosPicker` needs no library key
///    because `PHPickerViewController` runs out of process, which is why the
///    app was fine before this file existed.)
/// 2. The camera does not exist in the Simulator. `isAvailable` below is what
///    the caller gates on, so the button falls back to the library rather than
///    presenting a dead sheet.
struct CameraPicker: UIViewControllerRepresentable {
    /// Whether this device actually has a camera to present.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// JPEG data for the captured frame, already downscaled by the caller's
    /// existing upload path.
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
