import Foundation

/// Helper for managing security‑scoped bookmarks and file metadata.
enum ModelFileAccess {
    /// Create a security‑scoped bookmark for an external model file.
    static func makeBookmark(for url: URL) throws -> Data {
        return try url.bookmarkData(
            options: [.withSecurityScope],
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

    /// Resolve a stored bookmark and run a block while security access is active.
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
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try await body(url)
    }
}
