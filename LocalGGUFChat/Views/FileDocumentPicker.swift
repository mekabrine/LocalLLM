import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FileDocumentPicker: UIViewControllerRepresentable {
    let allowsMultipleSelection: Bool
    let onPick: (Result<[URL], Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let textTypes: [UTType] = [
            .plainText,
            .utf8PlainText,
            .commaSeparatedText,
            .json,
            .xml,
            .pdf,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "swift") ?? .plainText,
            UTType(filenameExtension: "py") ?? .plainText,
            UTType(filenameExtension: "js") ?? .plainText,
            UTType(filenameExtension: "html") ?? .plainText,
            UTType(filenameExtension: "css") ?? .plainText,
            UTType(filenameExtension: "log") ?? .plainText
        ]

        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: textTypes,
            asCopy: true
        )
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        controller.shouldShowFileExtensions = true
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

struct PendingFileAttachment: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let summary: String
    let text: String
}
