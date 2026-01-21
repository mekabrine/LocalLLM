
import Foundation
import UIKit

enum ModelFileAccessError: Error, LocalizedError {
    case cannotResolveBookmark
    case securityScopeDenied
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .cannotResolveBookmark: return "Could not open the model bookmark."
        case .securityScopeDenied: return "Could not access the model file (security scope)."
        case .fileMissing: return "The model file could not be found."
        }
    }
}

struct ModelFileAccess {
    static func resolveURL(from bookmark: Data) throws -> URL {
        var stale = false
        return try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    /// Synchronous access helper.
    static func withSecurityScopedURL<T>(bookmark: Data, body: (URL) throws -> T) throws -> T {
        let url = try resolveURL(from: bookmark)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ModelFileAccessError.fileMissing }
        guard url.startAccessingSecurityScopedResource() else { throw ModelFileAccessError.securityScopeDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }

    /// Async access helper that keeps the security scope open across `await` points.
    static func withSecurityScopedURLAsync<T>(bookmark: Data, body: (URL) async throws -> T) async throws -> T {
        let url = try resolveURL(from: bookmark)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ModelFileAccessError.fileMissing }
        guard url.startAccessingSecurityScopedResource() else { throw ModelFileAccessError.securityScopeDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return try await body(url)
    }

    static func fileSize(at url: URL) -> Int64 {
        (try? (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
    }

    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func displayName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
