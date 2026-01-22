import Foundation

/// Stores and resolves bookmark data for user-selected GGUF files.
/// On iOS, `.withSecurityScope` bookmark options are unavailable.
/// The correct approach is:
/// - create a minimal bookmark
/// - resolve without UI/mounting
/// - call `startAccessingSecurityScopedResource()` when you actually use the file
enum ModelFileAccess {
    private static let keyPrefix = "gguf_bookmark_"

    static func bookmarkKey(for modelID: UUID) -> String {
        keyPrefix + modelID.uuidString
    }

    static func saveBookmark(for url: URL, modelID: UUID) throws {
        // iOS: withSecurityScope is unavailable. Use minimalBookmark.
        let data = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey(for: modelID))
    }

    static func loadBookmarkedURL(modelID: UUID) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey(for: modelID)) else { return nil }
        var stale = false
        do {
            // Resolve bookmark without UI/mounting.
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            // If stale, try re-saving (best effort).
            if stale {
                try? saveBookmark(for: url, modelID: modelID)
            }
            return url
        } catch {
            return nil
        }
    }

    /// Execute a block while security-scoped access is active (if needed).
    /// Always use this when reading the model file.
    static func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }

    static func clearBookmark(modelID: UUID) {
        UserDefaults.standard.removeObject(forKey: bookmarkKey(for: modelID))
    }
}
