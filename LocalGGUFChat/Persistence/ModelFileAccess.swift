import Foundation

/// Helper for importing model files and reopening the app-managed local copy.
enum ModelFileAccess {
    enum ImportError: LocalizedError {
        case fileMissing(URL)
        case notEnoughSpace(required: Int64, available: Int64)

        var errorDescription: String? {
            switch self {
            case .fileMissing:
                return "The selected model file could not be opened. Move it to On My iPhone or iCloud Drive and try again."
            case let .notEnoughSpace(required, available):
                let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
                let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                return "There is not enough free storage to import this model. Required: \(requiredText). Available: \(availableText)."
            }
        }
    }

    /// Store the selected model in app-owned storage and create a bookmark to it.
    ///
    /// The UIKit picker is opened with `asCopy: true`, so iOS already gives the app
    /// a temporary local copy. For large GGUF files, moving that temporary copy is
    /// much safer than copying it again on the main app flow.
    static func makeBookmark(for url: URL) throws -> Data {
        let localURL = try moveOrCopyModelIntoAppStorage(from: url)
        return try localURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Display name (just the filename) for a model file.
    static func displayName(for url: URL) -> String {
        return url.lastPathComponent
    }

    /// File size in bytes.
    static func fileSize(at url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize {
                return Int64(size)
            }
        } catch { /* ignore */ }

        return 0
    }

    /// Resolve a stored bookmark and run a block with the resulting file URL.
    static func withSecurityScopedURLAsync<T>(
        bookmark: Data,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return try await body(url)
    }

    private static func moveOrCopyModelIntoAppStorage(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ImportError.fileMissing(sourceURL)
        }

        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelsDirectory = supportURL.appendingPathComponent("Models", isDirectory: true)
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(
            in: modelsDirectory,
            preferredName: sourceURL.lastPathComponent
        )

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            let requiredBytes = fileSize(at: sourceURL)
            if requiredBytes > 0 {
                let availableBytes = availableStorageBytes(near: modelsDirectory)
                if availableBytes > 0, availableBytes < requiredBytes {
                    throw ImportError.notEnoughSpace(required: requiredBytes, available: availableBytes)
                }
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }
    }

    private static func availableStorageBytes(near url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity
            }
        } catch { /* ignore */ }

        return 0
    }

    private static func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let baseName = (preferredName as NSString).deletingPathExtension
        let fileExtension = (preferredName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let nextName: String
            if fileExtension.isEmpty {
                nextName = "\(baseName)-\(index)"
            } else {
                nextName = "\(baseName)-\(index).\(fileExtension)"
            }
            candidate = directory.appendingPathComponent(nextName)
            index += 1
        }

        return candidate
    }
}
