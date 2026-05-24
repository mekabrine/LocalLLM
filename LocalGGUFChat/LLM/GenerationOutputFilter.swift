import Foundation

enum GenerationOutputFilter {
    private static let builtInStops = [
        "<|user|>", "<|assistant|>", "<|system|>",
        "### Instruction", "### Response", "### Input",
        "Person message:", "Assistant answer:", "Conversation:"
    ]

    private static let roleLabelPattern = #"(?im)^\s*(user|human|person|assistant|ai|bot|reply|question)\s*:"#

    static func filteredText(from rawText: String, userStops: [String]) -> (text: String, shouldStop: Bool) {
        guard !rawText.isEmpty else { return (rawText, false) }

        var bestRange: Range<String.Index>?

        for stop in userStops.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            if let range = rawText.range(of: stop, options: [.caseInsensitive]) {
                bestRange = earliest(bestRange, range)
            }
        }

        for stop in builtInStops {
            if let range = rawText.range(of: stop, options: [.caseInsensitive]) {
                bestRange = earliest(bestRange, range)
            }
        }

        if let range = rawText.range(of: roleLabelPattern, options: [.regularExpression]) {
            bestRange = earliest(bestRange, range)
        }

        if let bestRange {
            let safeText = rawText[..<bestRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(safeText), true)
        }

        return (rawText, false)
    }

    private static func earliest(_ current: Range<String.Index>?, _ candidate: Range<String.Index>) -> Range<String.Index> {
        guard let current else { return candidate }
        return candidate.lowerBound < current.lowerBound ? candidate : current
    }
}
