import Foundation
import SwiftLlama

/// SwiftLlama-backed local GGUF engine.
final class SwiftLlamaEngine: LLMEngine, @unchecked Sendable {
    private(set) var isLoaded: Bool = false

    private var loadedModelPath: String?
    private var loadedConfigurationKey: String?
    private var swiftLlama: SwiftLlama?

    func load(modelURL: URL) async throws {
        let path = modelURL.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(
                domain: "SwiftLlamaEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Model file is missing or cannot be opened."]
            )
        }

        if loadedModelPath != path {
            swiftLlama = nil
            loadedConfigurationKey = nil
            loadedModelPath = path
            isLoaded = false
        }
    }

    func unload() async {
        swiftLlama = nil
        loadedModelPath = nil
        loadedConfigurationKey = nil
        isLoaded = false
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        let fileName = loadedModelPath.map { URL(fileURLWithPath: $0).lastPathComponent }
        let template = ModelPromptTemplate.infer(from: fileName)
        let request = LLMPromptRequest(
            template: template,
            systemPrompt: "",
            userMessage: prompt,
            history: [],
            warnings: ["Using \(template.title) template inferred from the loaded model file name."]
        )
        return generate(request: request, config: config.addingStopSequences(template.stopSequences))
    }

    func generate(request: LLMPromptRequest, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try self.ensureLoadedForGeneration(config: config, template: request.template)

                    guard let swiftLlama = self.swiftLlama, self.isLoaded else {
                        continuation.finish(
                            throwing: NSError(
                                domain: "SwiftLlamaEngine",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
                            )
                        )
                        return
                    }

                    let nativePrompt = self.nativePrompt(from: request)
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

    private func nativePrompt(from request: LLMPromptRequest) -> Prompt {
        switch request.template {
        case .chatML:
            return Prompt(type: .chatML, systemPrompt: request.systemPrompt, userMessage: request.userMessage)
        case .llama3:
            return Prompt(type: .llama3, systemPrompt: request.systemPrompt, userMessage: request.userMessage)
        case .mistral:
            return Prompt(type: .mistral, systemPrompt: request.systemPrompt, userMessage: request.userMessage)
        case .phi:
            return Prompt(type: .phi, systemPrompt: request.systemPrompt, userMessage: request.userMessage)
        case .gemma:
            return Prompt(type: .gemma, systemPrompt: request.systemPrompt, userMessage: request.userMessage)
        case .alpaca:
            return Prompt(type: .alpaca, userMessage: request.userMessage)
        }
    }

    private func ensureLoadedForGeneration(config: GenerationConfig, template: ModelPromptTemplate = .alpaca) throws {
        guard let loadedModelPath else {
            throw NSError(
                domain: "SwiftLlamaEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
            )
        }

        let key = configurationKey(for: config, template: template)
        if swiftLlama != nil, loadedConfigurationKey == key {
            return
        }

        swiftLlama = nil
        isLoaded = false

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

    private func configurationKey(for config: GenerationConfig, template: ModelPromptTemplate) -> String {
        "\(template.rawValue)|\(config.temperature)|\(config.topP)|\(config.maxTokens)|\(config.stop.joined(separator: "\u{1f}"))"
    }

    private static func approximateTokenCount(in text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
