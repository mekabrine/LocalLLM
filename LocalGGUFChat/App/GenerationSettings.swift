import Foundation

@MainActor
final class GenerationSettings: ObservableObject {
    private enum Keys {
        static let temperature = "generation.temperature"
        static let topP = "generation.topP"
        static let maxTokens = "generation.maxTokens"
        static let stopSequences = "generation.stopSequences"
        static let defaultModelID = "models.defaultModelID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var temperature: Double {
        get { defaults.double(forKey: Keys.temperature) }
        set {
            defaults.set(newValue, forKey: Keys.temperature)
            objectWillChange.send()
        }
    }

    var topP: Double {
        get { defaults.double(forKey: Keys.topP) }
        set {
            defaults.set(newValue, forKey: Keys.topP)
            objectWillChange.send()
        }
    }

    var maxTokens: Int {
        get { defaults.integer(forKey: Keys.maxTokens) }
        set {
            defaults.set(newValue, forKey: Keys.maxTokens)
            objectWillChange.send()
        }
    }

    var stopSequencesText: String {
        get { defaults.string(forKey: Keys.stopSequences) ?? "User:" }
        set {
            defaults.set(newValue, forKey: Keys.stopSequences)
            objectWillChange.send()
        }
    }

    var defaultModelID: String {
        get { defaults.string(forKey: Keys.defaultModelID) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.defaultModelID)
            objectWillChange.send()
        }
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

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.temperature: 0.8,
            Keys.topP: 0.95,
            Keys.maxTokens: 512,
            Keys.stopSequences: "User:",
            Keys.defaultModelID: ""
        ])
    }
}
