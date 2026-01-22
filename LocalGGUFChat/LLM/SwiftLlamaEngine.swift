import Foundation
import SwiftLlama

/// Keeps the existing `LLMEngine` protocol untouched and fixes isolation checks
/// in the least invasive way by using `@preconcurrency` on the conformance.
actor SwiftLlamaEngine: @preconcurrency LLMEngine {

    private(set) var isLoaded: Bool = false

    private var llama: Swiftllama?

    init() {}

    func loadModel(at url: URL, config: ModelConfig) async throws {
        // If your project has a different config mapping, adjust here.
        // This assumes SwiftLlama provides something like `Configuration`.
        let llamaConfig = Configuration(
            modelPath: url.path,
            contextSize: config.contextSize,
            nThreads: config.threads,
            useGPU: config.useGPU
        )

        self.llama = Swiftllama(configuration: llamaConfig)
        self.isLoaded = true
    }

    func unload() {
        self.llama = nil
        self.isLoaded = false
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let llama else {
                        continuation.finish(throwing: NSError(domain: "SwiftLlamaEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]))
                        return
                    }

                    // Sampling config mapping (adjust to your SwiftLlama API if needed).
                    let sampling = SwiftLlama.Configuration.Sampling(
                        temperature: config.temperature,
                        topP: config.topP,
                        topK: config.topK,
                        repeatPenalty: config.repeatPenalty,
                        maxTokens: config.maxTokens
                    )

                    // IMPORTANT:
                    // Your earlier error was: `start(for:)` expects `Prompt` not `String`.
                    // The initializer below may need to be adjusted to match SwiftLlama's Prompt type.
                    // Common patterns are: `Prompt(prompt)` or `Prompt(text: prompt)` or `Prompt(content: prompt)`.
                    let p = Prompt(prompt) // <-- if this fails, change to the initializer that exists in SwiftLlama.

                    let stream = try await llama.start(for: p, sampling: sampling)

                    for try await token in stream {
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
