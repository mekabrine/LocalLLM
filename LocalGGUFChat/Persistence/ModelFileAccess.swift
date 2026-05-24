import Foundation

/// Helper for importing model files and reopening the app-managed local copy.
enum ModelFileAccess {
    /// Copy an imported model into Application Support and create an ordinary
    /// bookmark to that local copy. iOS does not support macOS-style
    /// security-scoped bookmarks, so keeping an app-owned copy is the most
    /// reliable way to reopen models after relaunch.
    static func makeBookmark(for url: URL) throws -> Data {
        let localURL = try copyModelIntoAppStorage(from: url)
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

    private static func copyModelIntoAppStorage(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
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

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
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
