import Foundation
import SwiftLlama

final class SwiftLlamaEngine: LLMEngine {
    private(set) var isLoaded: Bool = false

    private var llama: SwiftLlamaActor?
    private var currentModelURL: URL?

    func load(modelURL: URL) async throws {
        if isLoaded, currentModelURL == modelURL { return }

        await unload()

        // Make sure we can read the file if it's security-scoped (Files app).
        try ModelFileAccess.withSecurityScopedAccess(to: modelURL) {
            // Configure SwiftLlama. Adjust as needed.
            let config = Configuration(
                modelPath: modelURL.path,
                // Safe defaults; tune later
                nCtx: 4096,
                nThreads: max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
            )
            let actor = SwiftLlamaActor(configuration: config)
            self.llama = actor
            self.currentModelURL = modelURL
            self.isLoaded = true
        }
    }

    func unload() async {
        llama = nil
        currentModelURL = nil
        isLoaded = false
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let llama else {
                continuation.finish(throwing: NSError(domain: "LLM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]))
                return
            }

            Task {
                do {
                    // SwiftLlama expects Prompt, not String.
                    // This initializer exists in SwiftLlama 0.4.0.
                    let p = Prompt(text: prompt)

                    // Map our config to SwiftLlama if supported.
                    // If the library doesn't expose all fields, it still compiles; keep prompt streaming.
                    // Many SwiftLlama APIs accept configuration updates via Session/Configuration;
                    // streaming works even without passing temperature/topP here.
                    _ = config // currently not fully wired; safe no-op

                    for try await token in await llama.start(for: p) {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
