import Foundation

enum GenerationOutputFilter {
    private static let builtInStops = [
        "\nUser:", "\nHuman:", "\nAssistant:",
        "User:", "Human:", "Assistant:",
        "Person message:", "Assistant answer:", "Conversation:",
        "<|user|>", "<|assistant|>",
        "### Instruction", "### Response", "### Input"
    ]

    static func filteredText(from rawText: String, userStops: [String]) -> (text: String, shouldStop: Bool) {
        let stops = (userStops + builtInStops)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawText.isEmpty else { return (rawText, false) }

        var bestRange: Range<String.Index>?
        for stop in stops {
            if let range = rawText.range(of: stop, options: [.caseInsensitive]) {
                if bestRange == nil || range.lowerBound < bestRange!.lowerBound {
                    bestRange = range
                }
            }
        }

        if let bestRange {
            let safeText = rawText[..<bestRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(safeText), true)
        }

        return (rawText, false)
    }
}
