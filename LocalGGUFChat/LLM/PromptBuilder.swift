import Foundation

enum PromptBuilder {
    private static let maxMessages = 8
    private static let maxPromptCharacters = 3_500

    static func build(messages: [Message]) -> String {
        var lines: [String] = []

        for message in messages.suffix(maxMessages) {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            switch message.role {
            case .user:
                lines.append("User: \(text)")
            case .assistant:
                lines.append("Assistant: \(text)")
            }
        }

        lines.append("Assistant:")
        let prompt = lines.joined(separator: "\n")

        if prompt.count <= maxPromptCharacters {
            return prompt
        }

        let start = prompt.index(prompt.endIndex, offsetBy: -maxPromptCharacters)
        return String(prompt[start...])
    }
}
