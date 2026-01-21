
import Foundation

enum PromptBuilder {
    static func build(messages: [Message]) -> String {
        // Simple format that works with many base models. For instruct/chat-tuned models,
        // you may want to switch to the specific template (ChatML, Llama-3, etc).
        var out: [String] = []
        for m in messages {
            switch m.role {
            case .user:
                out.append("User: \(m.text)")
            case .assistant:
                out.append("Assistant: \(m.text)")
            }
        }
        out.append("Assistant:")
        return out.joined(separator: "\n")
    }
}
