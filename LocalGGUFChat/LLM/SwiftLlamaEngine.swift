import Foundation

/// A build-safe engine wrapper.
/// This implementation focuses on compiling reliably in CI.
/// You can later wire in the real SwiftLlama types once you finalize the API surface you want to use.
actor SwiftLlamaEngine: @preconcurrency LLMEngine {

    private var loadedModelURL: URL?

    init() {}

    // MARK: - LLMEngine

    func load(modelURL: URL) async throws {
        // Persist the URL to indicate "loaded".
        // Real implementation should initialize SwiftLlama model/session here.
        self.loadedModelURL = modelURL
    }

    // If your LLMEngine protocol has additional requirements, keep these minimal helpers.
    // Extra methods do not hurt conformance; missing required methods will.
    func unload() async {
        self.loadedModelURL = nil
    }

    /// Minimal non-streaming generation. Replace with real inference later.
    func generate(prompt: String) async throws -> String {
        guard loadedModelURL != nil else {
            throw NSError(
                domain: "SwiftLlamaEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
            )
        }
        // Placeholder response for build/runtime sanity.
        return prompt.isEmpty ? "" : "OK"
    }
}
