import Foundation

enum PromptBuilder {
    private struct PromptMessage {
        let role: MessageRole
        let text: String
    }

    static func build(
        messages: [Message],
        systemMessage: String,
        effectiveSettings: EffectiveGenerationSettings
    ) -> String {
        let cleanedMessages = messages.compactMap { message -> PromptMessage? in
            let text = clean(message.text)
            guard !text.isEmpty else { return nil }
            return PromptMessage(role: message.role, text: text)
        }

        let latestUserText = cleanedMessages.last(where: { $0.role == .user })?.text ?? ""
        let trimmedSystem = clean(systemMessage)
        let reasoning = reasoningInstruction(for: effectiveSettings.reasoningMode)

        let prompt: String
        switch effectiveSettings.promptStyle {
        case .raw:
            prompt = rawPrompt(system: trimmedSystem, reasoning: reasoning, latestUserText: latestUserText)
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

        return trim(prompt, to: effectiveSettings.promptCharacterLimit)
    }

    private static func rawPrompt(system: String, reasoning: String, latestUserText: String) -> String {
        var parts: [String] = []
        if !system.isEmpty { parts.append(system) }
        if !reasoning.isEmpty { parts.append(reasoning) }
        parts.append(latestUserText)
        return parts.joined(separator: "\n\n")
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
            lines.append("Helpful context from earlier:")
            lines.append(recent)
        }

        lines.append("Answer this directly:")
        lines.append(latestUserText)
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
            instruction += instruction.isEmpty ? "Helpful context:\n\(recent)" : "\n\nHelpful context:\n\(recent)"
        }

        if instruction.isEmpty {
            instruction = "Answer directly and only as the assistant."
        }

        return "Instruction:\n\(instruction)\n\nInput:\n\(latestUserText)\n\nAnswer:"
    }

    private static func previousContext(from messages: [PromptMessage], limit: Int) -> String {
        guard limit > 1 else { return "" }
        guard messages.count > 1 else { return "" }

        let contextMessages = messages.dropLast().suffix(max(0, limit - 1))
        return contextMessages.map { message in
            switch message.role {
            case .user:
                return "Earlier request: \(message.text)"
            case .assistant:
                return "Earlier answer: \(message.text)"
            }
        }.joined(separator: "\n")
    }

    private static func reasoningInstruction(for mode: ReasoningMode) -> String {
        switch mode {
        case .auto, .off:
            return ""
        case .fast:
            return "Think briefly, then give only the final answer."
        case .balanced:
            return "Use a short internal plan before answering, but do not show the plan."
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
