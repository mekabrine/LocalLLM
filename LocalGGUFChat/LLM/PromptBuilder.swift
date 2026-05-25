import Foundation

enum PromptBuilder {
    struct PromptPreview: Identifiable, Hashable {
        let id: String
        let style: PromptStyle
        let resolvedStyle: PromptStyle
        let prompt: String
        let warnings: [String]
    }

    private struct PromptMessage {
        let role: MessageRole
        let text: String
    }

    static func build(
        messages: [Message],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings
    ) -> String {
        buildResult(messages: messages, systemMessage: systemMessage, effectiveSettings: effectiveSettings).prompt
    }

    static func buildRequest(
        messages: [Message],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings,
        modelFileName: String?
    ) -> LLMPromptRequest {
        let cleanedMessages = messages.compactMap { message -> PromptMessage? in
            let text = clean(message.text)
            guard !text.isEmpty else { return nil }
            return PromptMessage(role: message.role, text: text)
        }

        return buildRequest(
            cleanedMessages: cleanedMessages,
            systemMessage: systemMessage,
            effectiveSettings: effectiveSettings,
            modelFileName: modelFileName
        )
    }

    static func buildResult(
        messages: [Message],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings
    ) -> (prompt: String, warnings: [String]) {
        let cleanedMessages = messages.compactMap { message -> PromptMessage? in
            let text = clean(message.text)
            guard !text.isEmpty else { return nil }
            return PromptMessage(role: message.role, text: text)
        }

        return legacyPromptResult(
            cleanedMessages: cleanedMessages,
            systemMessage: systemMessage,
            effectiveSettings: effectiveSettings
        )
    }

    @MainActor
    static func previews(
        sampleUserMessage: String,
        systemMessage: String,
        profile: GenerationProfile,
        settings: GenerationSettings
    ) -> [PromptPreview] {
        let cleanedMessages = [PromptMessage(role: .user, text: clean(sampleUserMessage))]
        return PromptStyle.allCases.map { style in
            let effective = settings.previewSettings(profile: profile, promptStyle: style)
            if style == .raw {
                let result = legacyPromptResult(
                    cleanedMessages: cleanedMessages,
                    systemMessage: systemMessage,
                    effectiveSettings: effective
                )
                return PromptPreview(
                    id: style.rawValue,
                    style: style,
                    resolvedStyle: effective.promptStyle,
                    prompt: result.prompt,
                    warnings: result.warnings
                )
            }

            let request = buildRequest(
                cleanedMessages: cleanedMessages,
                systemMessage: systemMessage,
                effectiveSettings: effective,
                modelFileName: sampleUserMessage
            )
            return PromptPreview(
                id: style.rawValue,
                style: style,
                resolvedStyle: effective.promptStyle,
                prompt: request.previewText,
                warnings: request.warnings
            )
        }
    }

    static func tinyAssistantRetryPrompt(userText: String) -> String {
        UniversalPromptTemplate.repairPrompt(user: clean(userText))
    }

    static func tinyAssistantRetryRequest(userText: String, modelFileName: String?) -> LLMPromptRequest {
        let template = ModelPromptTemplate.infer(from: modelFileName)
        return LLMPromptRequest(
            template: template,
            systemPrompt: "Reply to the user in one short assistant message.",
            userMessage: clean(userText),
            history: [],
            warnings: ["Retry used a short repair prompt with the \(template.title) template."]
        )
    }

    private static func legacyPromptResult(
        cleanedMessages: [PromptMessage],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings
    ) -> (prompt: String, warnings: [String]) {
        let latestUserText = cleanedMessages.last(where: { $0.role == .user })?.text ?? ""
        var warnings: [String] = []

        if effectiveSettings.promptStyle == .raw {
            warnings.append("Raw Debug sends exactly the latest user text and may cause completion-style models to continue the user's message.")
            return (trim(latestUserText, to: effectiveSettings.promptCharacterLimit), warnings)
        }

        let memory = memoryContext(from: cleanedMessages, limit: effectiveSettings.historyLimit)
        let prompt = UniversalPromptTemplate.prompt(system: systemMessage, memory: memory, user: latestUserText)
        let trimmed = trim(prompt, to: effectiveSettings.promptCharacterLimit)
        if trimmed.count < prompt.count {
            warnings.append("Prompt was trimmed to \(effectiveSettings.promptCharacterLimit) characters.")
        }
        return (trimmed, warnings)
    }

    private static func buildRequest(
        cleanedMessages: [PromptMessage],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings,
        modelFileName: String?
    ) -> LLMPromptRequest {
        let latestUserText = cleanedMessages.last(where: { $0.role == .user })?.text ?? ""
        var warnings: [String] = []
        let cleanSystem = clean(systemMessage).isEmpty ? GenerationSettings.defaultSystemMessage : clean(systemMessage)

        if effectiveSettings.promptStyle == .raw {
            warnings.append("Raw Debug sends exactly the latest user text and may cause completion-style models to continue the user's message.")
            return LLMPromptRequest(
                template: .alpaca,
                systemPrompt: "",
                userMessage: trim(latestUserText, to: effectiveSettings.promptCharacterLimit),
                history: [],
                warnings: warnings
            )
        }

        let template = ModelPromptTemplate.infer(from: modelFileName)
        if template == .alpaca {
            warnings.append("Model family was not recognized from the file name, so LocalLLM used the Alpaca fallback template.")
        } else {
            warnings.append("Using \(template.title) prompt formatting inferred from the model file name.")
        }

        let history = chatHistory(from: cleanedMessages, limit: effectiveSettings.historyLimit)
        let clippedHistory = history.map { turn in
            LLMChatTurn(
                user: clip(turn.user, to: 600),
                assistant: clip(turn.assistant, to: 600)
            )
        }
        let clippedUser = trim(latestUserText, to: effectiveSettings.promptCharacterLimit)
        if clippedUser.count < latestUserText.count {
            warnings.append("Latest user message was trimmed to \(effectiveSettings.promptCharacterLimit) characters.")
        }

        return LLMPromptRequest(
            template: template,
            systemPrompt: cleanSystem,
            userMessage: clippedUser,
            history: clippedHistory,
            warnings: warnings
        )
    }

    private static func memoryContext(from messages: [PromptMessage], limit: Int) -> String {
        guard limit > 1, messages.count > 1 else { return "" }
        let contextMessages = messages.dropLast().suffix(max(0, limit - 1))
        return contextMessages.map { message in
            let clipped = clip(message.text, to: 280)
            switch message.role {
            case .user:
                return "User: \(clipped)"
            case .assistant:
                return "Assistant: \(clipped)"
            }
        }.joined(separator: "\n")
    }

    private static func chatHistory(from messages: [PromptMessage], limit: Int) -> [LLMChatTurn] {
        guard limit > 1, messages.count > 1 else { return [] }
        let context = Array(messages.dropLast().suffix(max(0, limit - 1)))
        var turns: [LLMChatTurn] = []
        var pendingUser: String?

        for message in context {
            switch message.role {
            case .user:
                if let pendingUser {
                    turns.append(LLMChatTurn(user: pendingUser, assistant: ""))
                }
                pendingUser = message.text
            case .assistant:
                if let pendingUser {
                    turns.append(LLMChatTurn(user: pendingUser, assistant: message.text))
                    pendingUser = nil
                } else if !message.text.isEmpty {
                    turns.append(LLMChatTurn(user: "", assistant: message.text))
                }
            }
        }

        if let pendingUser {
            turns.append(LLMChatTurn(user: pendingUser, assistant: ""))
        }

        return turns.suffix(max(0, limit / 2)).map { $0 }
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clip(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "…"
    }

    private static func trim(_ prompt: String, to limit: Int) -> String {
        guard limit > 0, prompt.count > limit else { return prompt }
        let start = prompt.index(prompt.endIndex, offsetBy: -limit)
        return String(prompt[start...])
    }
}
