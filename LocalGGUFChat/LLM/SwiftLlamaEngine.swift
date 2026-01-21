
import Foundation
import SwiftLlama

actor SwiftLlamaEngine: LLMEngine {
    private var llama: SwiftLlama?
    private(set) var isLoaded: Bool = false
    private var loadedPath: String?

    func load(modelURL: URL) async throws {
        // Avoid reloading the same model repeatedly
        if isLoaded, loadedPath == modelURL.path { return }

        unload()
        let instance = try SwiftLlama(modelPath: modelURL.path)
        self.llama = instance
        self.loadedPath = modelURL.path
        self.isLoaded = true
    }

    func unload() {
        llama = nil
        loadedPath = nil
        isLoaded = false
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let llama else {
                        continuation.finish(throwing: NSError(domain: "SwiftLlamaEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]))
                        return
                    }

                    // SwiftLlama supports streaming via `AsyncSequence` returned from `start(for:)`.
                    // `maxTokens` and sampling params are library-dependent; keep this wrapper minimal and stable.
                    var produced = 0
                    for try await token in await llama.start(for: prompt) {
                        continuation.yield(token)
                        produced += 1
                        if produced >= config.maxTokens { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
