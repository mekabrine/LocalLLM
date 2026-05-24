import Foundation

enum HuggingFaceAPI {
    static func searchModels(query: String, purpose: ModelCapability, token: String) async throws -> [HuggingFaceRepo] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: searchText(query: query, purpose: purpose)),
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "full", value: "true")
        ]
        let object = try await requestJSON(url: components.url!, token: token)
        guard let array = object as? [[String: Any]] else {
            throw NSError(domain: "HuggingFace", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hugging Face returned an unexpected response."])
        }
        return array.compactMap(repo(from:))
    }

    static func repoInfo(repoID: String, token: String) async throws -> HuggingFaceRepo {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoID)") else { throw URLError(.badURL) }
        let object = try await requestJSON(url: url, token: token)
        guard let dictionary = object as? [String: Any], let repo = repo(from: dictionary) else {
            throw NSError(domain: "HuggingFace", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read this Hugging Face repository."])
        }
        return repo
    }

    private static func requestJSON(url: URL, token: String) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "HuggingFace", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Hugging Face returned HTTP \(http.statusCode). Public models do not need a token; clear a bad token if this persists."])
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            let text = String(data: data.prefix(180), encoding: .utf8) ?? "unreadable response"
            throw NSError(domain: "HuggingFace", code: 3, userInfo: [NSLocalizedDescriptionKey: "Hugging Face did not return model JSON: \(text)"])
        }
    }

    private static func repo(from dictionary: [String: Any]) -> HuggingFaceRepo? {
        guard let id = dictionary["id"] as? String ?? dictionary["modelId"] as? String ?? dictionary["_id"] as? String else { return nil }
        return HuggingFaceRepo(
            id: id,
            downloads: intValue(dictionary["downloads"]),
            likes: intValue(dictionary["likes"]),
            tags: dictionary["tags"] as? [String],
            gated: gatedValue(dictionary["gated"]),
            privateRepo: dictionary["private"] as? Bool,
            siblings: files(from: dictionary["siblings"])
        )
    }

    private static func files(from object: Any?) -> [HuggingFaceFile]? {
        guard let rows = object as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let name = row["rfilename"] as? String ?? row["path"] as? String else { return nil }
            return HuggingFaceFile(rfilename: name, size: int64Value(row["size"]))
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func gatedValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Bool { return value ? "true" : "false" }
        return nil
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
