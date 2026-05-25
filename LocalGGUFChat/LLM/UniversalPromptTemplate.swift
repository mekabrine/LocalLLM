import Foundation

enum UniversalPromptTemplate {
    static let startToken = "<LOCAL_LLM_START>"
    static let stopToken = "<LOCAL_LLM_STOP>"

    static let stopSequences = [
        stopToken,
        "\n<LOCAL_LLM_START>",
        "<|endoftext|>",
        "<|eot_id|>",
        "<|im_end|>"
    ]

    static func prompt(system: String, memory: String, user: String) -> String {
        var lines: [String] = [startToken]
        let cleanSystem = clean(system).isEmpty ? "Be helpful, direct, and concise. Reply only to the latest user message." : clean(system)
        lines.append("System:")
        lines.append(cleanSystem)

        let cleanMemory = clean(memory)
        if !cleanMemory.isEmpty {
            lines.append("")
            lines.append("Memory:")
            lines.append(cleanMemory)
        }

        lines.append("")
        lines.append("User:")
        lines.append(clean(user))
        lines.append("")
        lines.append("Assistant:")
        return lines.joined(separator: "\n")
    }

    static func repairPrompt(user: String) -> String {
        """
        \(startToken)
        System:
        Reply to the user in one short assistant message.

        User:
        \(clean(user))

        Assistant:
        """
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
