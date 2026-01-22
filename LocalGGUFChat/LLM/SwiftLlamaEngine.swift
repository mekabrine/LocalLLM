import Foundation

/// Minimal in-memory engine that satisfies the LLMEngine protocol.
/// You can replace the internals with SwiftLlama when ready.
final class SwiftLlamaEngine: LLMEngine {
    // MARK: - LLMEngine requirements
    private(set) var isLoaded: Bool = false
    private var modelURL: URL?

    /// Load a model. Real implementations would initialize the GGUF runtime here.
    func load(modelURL: URL) async throws {
        self.modelURL = modelURL
        self.isLoaded = true
    }

    /// Unload the current model.
    func unload() async {
        modelURL = nil
        isLoaded = false
    }

    /// Generate a token stream. This placeholder yields a single “OK” token.
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // If no model is loaded, throw an error.
            guard isLoaded else {
                continuation.finish(
                    throwing: NSError(
                        domain: "SwiftLlamaEngine",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
                    )
                )
                return
            }

            // Placeholder token stream.  Replace with real inference later.
            continuation.yield("OK")
            continuation.finish()
        }
    }
}
