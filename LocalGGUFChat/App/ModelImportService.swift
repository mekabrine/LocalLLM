import Foundation

enum ModelImportService {
    static func copyIntoModelsFolder(from sourceURL: URL) throws -> URL {
        let folder = try ModelFileAccess.visibleModelsDirectory()
        let destination = try uniqueDestination(in: folder, fileName: ModelFileAccess.displayName(for: sourceURL))
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { sourceURL.stopAccessingSecurityScopedResource() }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func uniqueDestination(in folder: URL, fileName: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = fileName.replacingOccurrences(of: ":", with: "-")
        var destination = folder.appendingPathComponent(safeName)
        let ext = destination.pathExtension
        let base = destination.deletingPathExtension().lastPathComponent
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            destination = folder.appendingPathComponent(name)
            counter += 1
        }
        return destination
    }
}
