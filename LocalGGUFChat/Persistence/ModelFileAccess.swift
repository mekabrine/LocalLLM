import Foundation

/// iOS-safe model file management.
/// Instead of security-scoped bookmarks (macOS-only `withSecurityScope`), we copy
/// selected model files into the app container and reference them from there.
final class ModelFileAccess {
    static let shared = ModelFileAccess()

    private init() {}

    enum ModelFileAccessError: LocalizedError {
        case unableToCreateModelsDirectory
        case sourceFileNotFound
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unableToCreateModelsDirectory:
                return "Unable to create the Models directory."
            case .sourceFileNotFound:
                return "Selected model file could not be found."
            case .copyFailed(let err):
                return "Failed to copy model file: \(err.localizedDescription)"
            }
        }
    }

    /// Directory inside the app sandbox where we keep imported models.
    private var modelsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    private func ensureModelsDirectoryExists() throws {
        let fm = FileManager.default
        let dir = modelsDirectoryURL

        if fm.fileExists(atPath: dir.path) { return }

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw ModelFileAccessError.unableToCreateModelsDirectory
        }
    }

    /// Copies a picked model file into the app sandbox (Application Support/Models).
    /// Returns the destination URL.
    func importModelFile(from pickedURL: URL) throws -> URL {
        try ensureModelsDirectoryExists()

        let fm = FileManager.default
        guard fm.fileExists(atPath: pickedURL.path) else {
            throw ModelFileAccessError.sourceFileNotFound
        }

        // Preserve filename; if collision exists, append a numeric suffix.
        let originalName = pickedURL.lastPathComponent
        var destURL = modelsDirectoryURL.appendingPathComponent(originalName)

        if fm.fileExists(atPath: destURL.path) {
            let base = destURL.deletingPathExtension().lastPathComponent
            let ext = destURL.pathExtension
            var i = 2
            while fm.fileExists(atPath: destURL.path) {
                let newName = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
                destURL = modelsDirectoryURL.appendingPathComponent(newName)
                i += 1
            }
        }

        do {
            // Remove any stale file at destination (shouldn’t happen with the collision logic, but safe).
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: pickedURL, to: destURL)
            return destURL
        } catch {
            throw ModelFileAccessError.copyFailed(error)
        }
    }

    /// Lists imported model files in the sandbox directory.
    func listImportedModels() -> [URL] {
        (try? ensureModelsDirectoryExists())

        let fm = FileManager.default
        let dir = modelsDirectoryURL

        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        // You can filter extensions here if you only want GGUF, etc.
        return items.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Deletes an imported model file.
    func deleteImportedModel(at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
