import Foundation

enum GenerationOutputQuality {
    static func shouldRetry(output: String, userText: String) -> Bool {
        let normalizedOutput = normalize(output)
        let normalizedUser = normalize(userText)
        guard !normalizedOutput.isEmpty else { return false }

        let leakPrefixes = [
            "internal plan", "task:", "response:", "instruction:",
            "according to your request", "write a response", "write an instruction",
            "user message:", "assistant reply:", "assistant answer:",
            "question:", "answer:", "previous request:"
        ]
        if leakPrefixes.contains(where: { normalizedOutput.hasPrefix($0) }) {
            return true
        }

        if normalizedUser == "hi" || normalizedUser == "hello" || normalizedUser == "hey" {
            let completionStarts = [
                "there", "there!", "world", "world!", "hello there", "hi there"
            ]
            if completionStarts.contains(where: { normalizedOutput.hasPrefix($0) }) {
                return true
            }
        }

        if normalizedUser.count <= 20, normalizedOutput.hasPrefix(normalizedUser + " ") {
            return true
        }

        return false
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
