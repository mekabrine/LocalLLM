import Foundation
import Combine
import Security

enum ModelRuntimeSupport: String, CaseIterable, Identifiable, Hashable {
    case runsNow
    case needsImageBackend
    case needsSpeechBackend
    case needsVoiceBackend
    case needsVisionBackend
    case unsupportedFormat
    case tooLarge
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runsNow: return "Runs Now"
        case .needsImageBackend: return "Needs Image Backend"
        case .needsSpeechBackend: return "Needs Speech Backend"
        case .needsVoiceBackend: return "Needs Voice Backend"
        case .needsVisionBackend: return "Needs Vision Backend"
        case .unsupportedFormat: return "Unsupported Format"
        case .tooLarge: return "Too Large"
        case .unknown: return "Unknown Runtime"
        }
    }

    var detail: String {
        switch self {
        case .runsNow: return "This model can be tried with the current local text backend."
        case .needsImageBackend: return "This model can be downloaded and saved, but image rendering requires a dedicated image backend."
        case .needsSpeechBackend: return "This model can be downloaded and saved, but speech-to-text requires a dedicated speech backend."
        case .needsVoiceBackend: return "This model can be downloaded and saved, but text-to-speech requires a dedicated voice backend."
        case .needsVisionBackend: return "This model can be downloaded and saved, but vision requires a dedicated vision backend."
        case .unsupportedFormat: return "This file format is not supported by the current runtime."
        case .tooLarge: return "This model is probably too large for this device."
        case .unknown: return "The app cannot confirm whether this model can run yet."
        }
    }

    static func resolve(purpose: ModelCapability, fileName: String, fileSize: Int64) -> ModelRuntimeSupport {
        let lower = fileName.lowercased()
        switch purpose {
        case .text, .fileHelper:
            guard lower.hasSuffix(".gguf") else { return .unsupportedFormat }
            let compatibility = ModelCapabilityInfo.infer(name: fileName, fileSize: fileSize, purposeOverride: .text).compatibility
            if compatibility == .tooLarge { return .tooLarge }
            return .runsNow
        case .imageGeneration:
            return .needsImageBackend
        case .speechToText:
            return .needsSpeechBackend
        case .textToSpeech:
            return .needsVoiceBackend
        case .vision:
            return .needsVisionBackend
        case .unknown:
            return .unknown
        }
    }
}

struct HuggingFaceRepo: Identifiable, Hashable, Decodable {
    let id: String
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let gated: String?
    let privateRepo: Bool?
    let siblings: [HuggingFaceFile]?

    enum CodingKeys: String, CodingKey {
        case id
        case downloads
        case likes
        case tags
        case gated
        case privateRepo = "private"
        case siblings
    }

    var title: String { id }
    var isGated: Bool { gated != nil && gated != "false" }
}

struct HuggingFaceFile: Identifiable, Hashable, Decodable {
    let rfilename: String
    let size: Int64?

    var id: String { rfilename }
    var displayName: String { URL(fileURLWithPath: rfilename).lastPathComponent }
    var fileExtension: String { URL(fileURLWithPath: rfilename).pathExtension.lowercased() }

    func runtimeSupport(for purpose: ModelCapability) -> ModelRuntimeSupport {
        ModelRuntimeSupport.resolve(purpose: purpose, fileName: rfilename, fileSize: size ?? 0)
    }
}

enum HuggingFaceTokenStore {
    private static let service = "LocalLLM.HuggingFace"
    private static let account = "accessToken"

    static func readToken() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }

    static func saveToken(_ token: String) {
        deleteToken()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum HuggingFaceService {
    static func searchModels(query: String, purpose: ModelCapability, token: String) async throws -> [HuggingFaceRepo] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: searchText(query: query, purpose: purpose)),
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "full", value: "true")
        ]
        return try await request([HuggingFaceRepo].self, url: components.url!, token: token)
    }

    static func repoInfo(repoID: String, token: String) async throws -> HuggingFaceRepo {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoID)") else {
            throw URLError(.badURL)
        }
        return try await request(HuggingFaceRepo.self, url: url, token: token)
    }

    static func downloadURL(repoID: String, filename: String) throws -> URL {
        let encodedFile = filename.split(separator: "/").map { part in
            String(part).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
        }.joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encodedFile)") else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func request<T: Decodable>(_ type: T.Type, url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty { request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "HuggingFace", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Hugging Face returned HTTP \(http.statusCode). Check token, gated access, or rate limits."])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func searchText(query: String, purpose: ModelCapability) -> String {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        switch purpose {
        case .text, .fileHelper: return "gguf q4"
        case .imageGeneration: return "coreml stable diffusion"
        case .speechToText: return "whisper"
        case .textToSpeech: return "piper tts"
        case .vision: return "vision gguf"
        case .unknown: return "gguf"
        }
    }
}

struct HuggingFaceDownloadItem: Identifiable, Hashable {
    enum State: String, Hashable {
        case queued
        case downloading
        case saved
        case failed
    }

    let id: UUID
    let repoID: String
    let filename: String
    let purpose: ModelCapability
    var state: State
    var detail: String
}

@MainActor
final class HuggingFaceDownloadStore: ObservableObject {
    static let shared = HuggingFaceDownloadStore()

    @Published private(set) var downloads: [HuggingFaceDownloadItem] = []

    func download(repoID: String, file: HuggingFaceFile, purpose: ModelCapability, token: String) {
        let id = UUID()
        downloads.insert(HuggingFaceDownloadItem(id: id, repoID: repoID, filename: file.rfilename, purpose: purpose, state: .queued, detail: "Queued"), at: 0)

        Task {
            await update(id: id, state: .downloading, detail: "Downloading to Models folder…")
            do {
                let remoteURL = try HuggingFaceService.downloadURL(repoID: repoID, filename: file.rfilename)
                var request = URLRequest(url: remoteURL)
                let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanToken.isEmpty { request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization") }
                let (tempURL, response) = try await URLSession.shared.download(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(domain: "HuggingFace", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)."])
                }

                let destination = try uniqueDestinationURL(for: file.displayName)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: tempURL, to: destination)

                let bookmark = try ModelFileAccess.makeBookmarkForVisibleModel(at: destination)
                let model = try PersistenceController.shared.upsertModel(
                    from: bookmark,
                    displayName: destination.lastPathComponent,
                    originalPath: destination.path,
                    fileSize: ModelFileAccess.fileSize(at: destination)
                )
                ModelPurposeStore.setPurpose(purpose, for: model)
                await update(id: id, state: .saved, detail: "Saved as \(purpose.importTitle) in LocalLLM/Models.")
            } catch {
                await update(id: id, state: .failed, detail: error.localizedDescription)
            }
        }
    }

    func clearFinished() {
        downloads.removeAll { $0.state == .saved || $0.state == .failed }
    }

    private func update(id: UUID, state: HuggingFaceDownloadItem.State, detail: String) async {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].state = state
            downloads[index].detail = detail
        }
    }

    private func uniqueDestinationURL(for fileName: String) throws -> URL {
        let folder = try ModelFileAccess.visibleModelsDirectory()
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
