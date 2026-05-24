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
        return buildResult(cleanedMessages: cleanedMessages, systemMessage: systemMessage, effectiveSettings: effectiveSettings)
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
            let result = buildResult(cleanedMessages: cleanedMessages, systemMessage: systemMessage, effectiveSettings: effective)
            return PromptPreview(
                id: style.rawValue,
                style: style,
                resolvedStyle: effective.promptStyle,
                prompt: result.prompt,
                warnings: result.warnings
            )
        }
    }

    static func tinyAssistantRetryPrompt(userText: String) -> String {
        tinyAssistantPrompt(latestUserText: clean(userText))
    }

    private static func buildResult(
        cleanedMessages: [PromptMessage],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings
    ) -> (prompt: String, warnings: [String]) {
        let latestUserText = cleanedMessages.last(where: { $0.role == .user })?.text ?? ""
        let trimmedSystem = clean(systemMessage)
        let reasoning = reasoningInstruction(for: effectiveSettings.reasoningMode)
        var warnings: [String] = []

        if effectiveSettings.usesSmallModelProtection {
            warnings.append("Small Model Protection is active: history is limited, reasoning is disabled, and Plain uses a tiny assistant wrapper.")
        }

        let prompt: String
        switch effectiveSettings.promptStyle {
        case .plain:
            if !trimmedSystem.isEmpty && effectiveSettings.usesSmallModelProtection {
                warnings.append("System message ignored for Plain small-model mode.")
            }
            prompt = tinyAssistantPrompt(latestUserText: latestUserText)
        case .raw:
            warnings.append("Raw Debug sends exactly the latest user text and may cause completion-style models to continue the user's message.")
            prompt = latestUserText
        case .simple, .auto:
            prompt = simplePrompt(
                messages: cleanedMessages,
                system: trimmedSystem,
                reasoning: reasoning,
                latestUserText: latestUserText,
                historyLimit: effectiveSettings.historyLimit
            )
        case .instruct:
            prompt = instructPrompt(
                messages: cleanedMessages,
                system: trimmedSystem,
                reasoning: reasoning,
                latestUserText: latestUserText,
                historyLimit: effectiveSettings.historyLimit
            )
        }

        let trimmed = trim(prompt, to: effectiveSettings.promptCharacterLimit)
        if trimmed.count < prompt.count {
            warnings.append("Prompt was trimmed to \(effectiveSettings.promptCharacterLimit) characters.")
        }

        return (trimmed, warnings)
    }

    private static func tinyAssistantPrompt(latestUserText: String) -> String {
        """
        You are the assistant. Write only a short assistant reply to the user. Do not continue the user's message.

        User message:
        \(latestUserText)

        Assistant reply:
        """
    }

    private static func simplePrompt(
        messages: [PromptMessage],
        system: String,
        reasoning: String,
        latestUserText: String,
        historyLimit: Int
    ) -> String {
        var lines: [String] = []
        if !system.isEmpty { lines.append(system) }
        if !reasoning.isEmpty { lines.append(reasoning) }

        let recent = previousContext(from: messages, limit: historyLimit)
        if !recent.isEmpty {
            lines.append("Earlier context:")
            lines.append(recent)
        }

        lines.append("Question:")
        lines.append(latestUserText)
        lines.append("Answer:")
        return lines.joined(separator: "\n\n")
    }

    private static func instructPrompt(
        messages: [PromptMessage],
        system: String,
        reasoning: String,
        latestUserText: String,
        historyLimit: Int
    ) -> String {
        var instruction = system
        if !reasoning.isEmpty {
            instruction += instruction.isEmpty ? reasoning : "\n" + reasoning
        }

        let recent = previousContext(from: messages, limit: historyLimit)
        if !recent.isEmpty {
            instruction += instruction.isEmpty ? "Earlier context:\n\(recent)" : "\n\nEarlier context:\n\(recent)"
        }

        if instruction.isEmpty {
            instruction = "Answer directly and only as the assistant."
        }

        return "Task:\n\(instruction)\n\nMessage:\n\(latestUserText)\n\nReply:"
    }

    private static func previousContext(from messages: [PromptMessage], limit: Int) -> String {
        guard limit > 1 else { return "" }
        guard messages.count > 1 else { return "" }

        let contextMessages = messages.dropLast().suffix(max(0, limit - 1))
        return contextMessages.map { message in
            switch message.role {
            case .user:
                return "Previous request: \(message.text)"
            case .assistant:
                return "Previous answer: \(message.text)"
            }
        }.joined(separator: "\n")
    }

    private static func reasoningInstruction(for mode: ReasoningMode) -> String {
        switch mode {
        case .auto, .off:
            return ""
        case .fast:
            return "Give a brief final answer."
        case .balanced:
            return "Check the answer before responding, but show only the final answer."
        case .deep:
            return "Think carefully and check the answer before responding, but show only the final answer."
        }
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trim(_ prompt: String, to limit: Int) -> String {
        guard limit > 0, prompt.count > limit else { return prompt }
        let start = prompt.index(prompt.endIndex, offsetBy: -limit)
        return String(prompt[start...])
    }
}
