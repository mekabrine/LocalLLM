import Foundation
import SwiftLlama

/// SwiftLlama-backed local GGUF engine.
final class SwiftLlamaEngine: LLMEngine {
    private(set) var isLoaded: Bool = false

    private var loadedModelPath: String?
    private var loadedConfigurationKey: String?
    private var swiftLlama: SwiftLlama?

    func load(modelURL: URL) async throws {
        let path = modelURL.path

        if isLoaded, loadedModelPath == path, swiftLlama != nil {
            return
        }

        swiftLlama = nil
        loadedModelPath = path
        loadedConfigurationKey = nil
        swiftLlama = try SwiftLlama(modelPath: path)
        isLoaded = true
    }

    func unload() async {
        swiftLlama = nil
        loadedModelPath = nil
        loadedConfigurationKey = nil
        isLoaded = false
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            do {
                try ensureLoadedForGeneration(config: config)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            guard let swiftLlama, isLoaded else {
                continuation.finish(
                    throwing: NSError(
                        domain: "SwiftLlamaEngine",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
                    )
                )
                return
            }

            let nativePrompt = Prompt(type: .llama3, userMessage: prompt)

            let task = Task {
                do {
                    var approximateTokens = 0

                    for try await token in await swiftLlama.start(for: nativePrompt) {
                        try Task.checkCancellation()

                        if !token.isEmpty {
                            approximateTokens += Self.approximateTokenCount(in: token)
                            continuation.yield(token)
                        }

                        if config.maxTokens > 0, approximateTokens >= config.maxTokens {
                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func ensureLoadedForGeneration(config: GenerationConfig) throws {
        guard let loadedModelPath else {
            throw NSError(
                domain: "SwiftLlamaEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
            )
        }

        let key = configurationKey(for: config)
        if swiftLlama != nil, loadedConfigurationKey == key {
            return
        }

        swiftLlama = try SwiftLlama(
            modelPath: loadedModelPath,
            modelConfiguration: Configuration(
                topP: Float(config.topP),
                temperature: Float(config.temperature),
                stopSequence: nil,
                maxTokenCount: config.maxTokens,
                stopTokens: config.stop
            )
        )
        loadedConfigurationKey = key
        isLoaded = true
    }

    private func configurationKey(for config: GenerationConfig) -> String {
        "\(config.temperature)|\(config.topP)|\(config.maxTokens)|\(config.stop.joined(separator: "\u{1f}"))"
    }

    private static func approximateTokenCount(in text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
