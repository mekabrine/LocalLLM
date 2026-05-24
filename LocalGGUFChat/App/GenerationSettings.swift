import Foundation
import SwiftUI

@MainActor
final class GenerationSettings: ObservableObject {
    @AppStorage("generation.temperature") var temperature: Double = 0.8 {
        willSet { objectWillChange.send() }
    }

    @AppStorage("generation.topP") var topP: Double = 0.95 {
        willSet { objectWillChange.send() }
    }

    @AppStorage("generation.maxTokens") var maxTokens: Int = 512 {
        willSet { objectWillChange.send() }
    }

    @AppStorage("generation.stopSequences") var stopSequencesText: String = "User:" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("models.defaultModelID") var defaultModelID: String = "" {
        willSet { objectWillChange.send() }
    }

    var stopSequences: [String] {
        stopSequencesText
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var generationConfig: GenerationConfig {
        GenerationConfig(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stopSequences
        )
    }

    func resetSamplingDefaults() {
        temperature = 0.8
        topP = 0.95
        maxTokens = 512
        stopSequencesText = "User:"
    }
}
