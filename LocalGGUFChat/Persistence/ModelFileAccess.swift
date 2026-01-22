import Foundation

enum ModelFileAccess {
    /// Create a security-scoped bookmark for an external model file URL.
    static func makeBookmark(for url: URL) throws -> Data {
        // Security-scoped bookmarks are the right approach for user-picked files.
        // Works on iOS / iOS Simulator.
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Human-friendly display name for the selected model file.
    static func displayName(for url: URL) -> String {
        // If you later want a nicer name, you can read resource values (like .localizedNameKey).
        return url.lastPathComponent
    }

    /// File size in bytes for the URL.
    static func fileSize(at url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize {
                return Int64(size)
            }
        } catch {
            // Fall through to FileManager as a secondary attempt.
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let n = attrs[.size] as? NSNumber {
                return n.int64Value
            }
        } catch {
            // Ignore; return 0 if unavailable.
        }

        return 0
    }

    /// Resolve a bookmark into a URL and run an async block while holding a security-scoped access token.
    static func withSecurityScopedURLAsync<T>(
        bookmark: Data,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        var isStale = false

        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Even if stale, the URL may still work; if you want, you can regenerate the bookmark when stale.
        return try await body(url)
    }
}
