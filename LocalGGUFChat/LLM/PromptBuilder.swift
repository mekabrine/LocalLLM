import Foundation

enum PromptBuilder {
    private static let maxMessages = 8
    private static let maxPromptCharacters = 3_000

    static func build(messages: [Message]) -> String {
        var lines: [String] = [
            "You are a helpful on-device assistant. Answer only as the assistant.",
            "Do not write labels like User:, Human:, or Assistant: in your answer.",
            "Do not continue the conversation for the person.",
            "",
            "Conversation:"
        ]

        for message in messages.suffix(maxMessages) {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            switch message.role {
            case .user:
                lines.append("Person message:")
                lines.append(text)
            case .assistant:
                lines.append("Assistant answer:")
                lines.append(text)
            }
            lines.append("")
        }

        lines.append("Write the next assistant answer:")
        let prompt = lines.joined(separator: "\n")

        if prompt.count <= maxPromptCharacters {
            return prompt
        }

        let start = prompt.index(prompt.endIndex, offsetBy: -maxPromptCharacters)
        return String(prompt[start...])
    }
}
