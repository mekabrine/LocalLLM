import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ModelDocumentPicker: UIViewControllerRepresentable {
    let allowsMultipleSelection: Bool
    let onPick: (Result<[URL], Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet

        if #available(iOS 14.0, *) {
            controller.shouldShowFileExtensions = true
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (Result<[URL], Error>) -> Void

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(.success([]))
        }
    }
}
