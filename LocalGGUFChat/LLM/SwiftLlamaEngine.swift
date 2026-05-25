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
        let request = legacyPromptRequest(from: prompt, modelFileName: fileName)
        let routedConfig = config.addingStopSequences(request.template.stopSequences)
        return generate(request: request, config: routedConfig)
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
        let history = request.history.map { Chat(user: $0.user, bot: $0.assistant) }

        switch request.template {
        case .chatML:
            return Prompt(type: .chatML, systemPrompt: request.systemPrompt, userMessage: request.userMessage, history: history)
        case .llama3:
            return Prompt(type: .llama3, systemPrompt: request.systemPrompt, userMessage: request.userMessage, history: history)
        case .mistral:
            return Prompt(type: .mistral, systemPrompt: request.systemPrompt, userMessage: mistralUserMessage(from: request), history: history)
        case .phi:
            return Prompt(type: .phi, systemPrompt: request.systemPrompt, userMessage: request.userMessage, history: history)
        case .gemma:
            return Prompt(type: .gemma, systemPrompt: request.systemPrompt, userMessage: request.userMessage, history: history)
        case .alpaca:
            return Prompt(type: .alpaca, userMessage: alpacaUserMessage(from: request))
        }
    }

    private func legacyPromptRequest(from prompt: String, modelFileName: String?) -> LLMPromptRequest {
        let template = ModelPromptTemplate.infer(from: modelFileName)
        let parsed = parseLocalPrompt(prompt)
        return LLMPromptRequest(
            template: template,
            systemPrompt: parsed.systemPrompt,
            userMessage: parsed.userMessage,
            history: parsed.history,
            warnings: ["Using \(template.title) template inferred from the loaded model file name."]
        )
    }

    private func parseLocalPrompt(_ prompt: String) -> (systemPrompt: String, userMessage: String, history: [LLMChatTurn]) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = section(named: "System", in: trimmed, before: ["Memory", "User", "Assistant"])
        let memory = section(named: "Memory", in: trimmed, before: ["User", "Assistant"])
        let user = section(named: "User", in: trimmed, before: ["Assistant"])

        return (
            systemPrompt: system.isEmpty ? GenerationSettings.defaultSystemMessage : system,
            userMessage: user.isEmpty ? trimmed : user,
            history: parseMemory(memory)
        )
    }

    private func section(named name: String, in text: String, before possibleNextNames: [String]) -> String {
        let marker = "\n\(name):\n"
        let prefixed = "\n" + text
        guard let markerRange = prefixed.range(of: marker) else { return "" }
        let start = markerRange.upperBound
        var end = prefixed.endIndex

        for next in possibleNextNames {
            let nextMarker = "\n\(next):\n"
            if let range = prefixed.range(of: nextMarker, range: start..<prefixed.endIndex), range.lowerBound < end {
                end = range.lowerBound
            }
        }

        return String(prefixed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseMemory(_ memory: String) -> [LLMChatTurn] {
        guard !memory.isEmpty else { return [] }
        var turns: [LLMChatTurn] = []
        var pendingUser: String?

        for line in memory.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("user: ") {
                if let pendingUser {
                    turns.append(LLMChatTurn(user: pendingUser, assistant: ""))
                }
                pendingUser = String(text.dropFirst(6))
            } else if text.lowercased().hasPrefix("assistant: ") {
                let assistant = String(text.dropFirst(11))
                if let pendingUser {
                    turns.append(LLMChatTurn(user: pendingUser, assistant: assistant))
                    pendingUser = nil
                } else {
                    turns.append(LLMChatTurn(user: "", assistant: assistant))
                }
            }
        }

        if let pendingUser {
            turns.append(LLMChatTurn(user: pendingUser, assistant: ""))
        }

        return turns
    }

    private func alpacaUserMessage(from request: LLMPromptRequest) -> String {
        var sections: [String] = []
        let system = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            sections.append("System:\n\(system)")
        }

        if !request.history.isEmpty {
            let memory = request.history.map { turn in
                [
                    turn.user.isEmpty ? nil : "User: \(turn.user)",
                    turn.assistant.isEmpty ? nil : "Assistant: \(turn.assistant)"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

            if !memory.isEmpty {
                sections.append("Conversation so far:\n\(memory)")
            }
        }

        sections.append("User:\n\(request.userMessage)\n\nAssistant:")
        return sections.joined(separator: "\n\n")
    }

    private func mistralUserMessage(from request: LLMPromptRequest) -> String {
        let system = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !system.isEmpty else { return request.userMessage }
        return "\(system)\n\n\(request.userMessage)"
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
