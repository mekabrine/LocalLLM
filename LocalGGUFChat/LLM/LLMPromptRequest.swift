import Foundation

struct LLMChatTurn: Sendable, Hashable {
    let user: String
    let assistant: String
}

struct LLMPromptRequest: Sendable, Hashable {
    let template: ModelPromptTemplate
    let systemPrompt: String
    let userMessage: String
    let history: [LLMChatTurn]
    let warnings: [String]

    var previewText: String {
        ModelPromptPreview.render(request: self)
    }
}

enum ModelPromptTemplate: String, CaseIterable, Sendable, Hashable {
    case alpaca
    case chatML
    case llama3
    case mistral
    case phi
    case gemma

    var title: String {
        switch self {
        case .alpaca: return "Alpaca"
        case .chatML: return "ChatML"
        case .llama3: return "Llama 3"
        case .mistral: return "Mistral"
        case .phi: return "Phi"
        case .gemma: return "Gemma"
        }
    }

    var shortTitle: String {
        switch self {
        case .alpaca: return "Alpaca"
        case .chatML: return "ChatML"
        case .llama3: return "Llama3"
        case .mistral: return "Mistral"
        case .phi: return "Phi"
        case .gemma: return "Gemma"
        }
    }

    var subtitle: String {
        switch self {
        case .alpaca:
            return "Fallback for older Alpaca-style or unknown instruction models."
        case .chatML:
            return "Used by Qwen, Qwen2/2.5/3, DeepSeek, Yi, SmolLM, and many OpenAI-style GGUFs."
        case .llama3:
            return "Uses Llama 3 header and end-of-turn tokens."
        case .mistral:
            return "Uses Mistral/Instruct [INST] wrapping."
        case .phi:
            return "Uses Phi role tokens."
        case .gemma:
            return "Uses Gemma start/end turn markers."
        }
    }

    var stopSequences: [String] {
        switch self {
        case .alpaca:
            return ["\n### Instruction", "\n### Response", "\nUser:", "\nHuman:"]
        case .chatML:
            return ["<|im_end|>", "<|endoftext|>", "<|user|>", "<|system|>", "<|im_start|>user"]
        case .llama3:
            return ["<|eot_id|>", "<|end_of_text|>", "<|start_header_id|>user", "<|start_header_id|>system"]
        case .mistral:
            return ["</s>", "[INST]", "[/INST]", "<s>"]
        case .phi:
            return ["<|end|>", "<|user|>", "<|system|>"]
        case .gemma:
            return ["<end_of_turn>", "<start_of_turn>user", "<start_of_turn>model"]
        }
    }

    static var universalStopSequences: [String] {
        Array(Set(allCases.flatMap(\.stopSequences)))
    }

    static func infer(from fileName: String?) -> ModelPromptTemplate {
        let name = (fileName ?? "").lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".gguf", with: "")

        if name.contains("gemma") { return .gemma }
        if name.contains("llama-3") || name.contains("llama3") || name.contains("llama-4") || name.contains("llama4") { return .llama3 }
        if name.contains("mistral") || name.contains("mixtral") || name.contains("ministral") { return .mistral }
        if name.contains("phi-") || name.contains("phi3") || name.contains("phi-3") || name.contains("phi4") || name.contains("phi-4") { return .phi }
        if name.contains("qwen") || name.contains("deepseek") || name.contains("smollm") || name.contains("yi-") || name.contains("openchat") || name.contains("chatml") { return .chatML }
        return .alpaca
    }
}

private enum ModelPromptPreview {
    static func render(request: LLMPromptRequest) -> String {
        let history = request.history.suffix(4).map { turn in
            "User: \(turn.user)\nAssistant: \(turn.assistant)"
        }.joined(separator: "\n")

        switch request.template {
        case .chatML:
            return [
                "<|im_start|>system\n\(request.systemPrompt)<|im_end|>",
                history,
                "<|im_start|>user\n\(request.userMessage)<|im_end|>",
                "<|im_start|>assistant"
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        case .llama3:
            return [
                "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(request.systemPrompt)<|eot_id|>",
                history,
                "<|start_header_id|>user<|end_header_id|>\n\n\(request.userMessage)<|eot_id|>",
                "<|start_header_id|>assistant<|end_header_id|>"
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        case .mistral:
            return "<s>[INST] \(request.systemPrompt)\n\n\(request.userMessage) [/INST]"
        case .phi:
            return "\(request.systemPrompt)\n<|user|>\n\(request.userMessage)\n<|end|>\n<|assistant|>"
        case .gemma:
            return "<start_of_turn>system\n\(request.systemPrompt)\n<end_of_turn>\n<start_of_turn>user\n\(request.userMessage)\n<end_of_turn>\n<start_of_turn>model"
        case .alpaca:
            return "Below is an instruction that describes a task.\n\n\(request.userMessage)"
        }
    }
}
