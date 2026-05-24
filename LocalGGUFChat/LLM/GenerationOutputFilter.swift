import Foundation

enum GenerationOutputFilter {
    private static let builtInStops = [
        "<|user|>", "<|assistant|>", "<|system|>",
        "### Instruction", "### Response", "### Input",
        "Person message:", "Conversation:",
        "\nUser:", "\nHuman:", "\nPerson:", "\nQuestion:",
        "\nLatest user message:", "\nEarlier chat facts:"
    ]

    private static let leadingLabels = [
        "Assistant answer:", "Assistant reply:", "Assistant:", "Reply:", "Answer:", "Bot:", "AI:"
    ]

    private static let laterRoleLabelPattern = #"(?im)\n\s*(user|human|person|assistant|ai|bot|question)\s*:"#

    static func filteredText(from rawText: String, userStops: [String]) -> (text: String, shouldStop: Bool) {
        guard !rawText.isEmpty else { return (rawText, false) }

        var working = stripLeadingLabels(from: rawText)
        var bestRange: Range<String.Index>?

        for stop in userStops.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            if let range = working.range(of: stop, options: [.caseInsensitive]), range.lowerBound > working.startIndex {
                bestRange = earliest(bestRange, range)
            }
        }

        for stop in builtInStops {
            if let range = working.range(of: stop, options: [.caseInsensitive]), range.lowerBound > working.startIndex {
                bestRange = earliest(bestRange, range)
            }
        }

        if let range = working.range(of: laterRoleLabelPattern, options: [.regularExpression]), range.lowerBound > working.startIndex {
            bestRange = earliest(bestRange, range)
        }

        if let bestRange {
            let safeText = working[..<bestRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(safeText), true)
        }

        working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return (working, false)
    }

    private static func stripLeadingLabels(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for label in leadingLabels {
                if result.lowercased().hasPrefix(label.lowercased()) {
                    result = String(result.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    private static func earliest(_ current: Range<String.Index>?, _ candidate: Range<String.Index>) -> Range<String.Index> {
        guard let current else { return candidate }
        return candidate.lowerBound < current.lowerBound ? candidate : current
    }
}
