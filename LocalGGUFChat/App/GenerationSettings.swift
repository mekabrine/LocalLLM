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

    func applyPreset(_ preset: GenerationPreset) {
        temperature = preset.temperature
        topP = preset.topP
        maxTokens = preset.maxTokens
    }

    func resetSamplingDefaults() {
        applyPreset(.balanced)
        stopSequencesText = "User:"
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.temperature: GenerationPreset.balanced.temperature,
            Keys.topP: GenerationPreset.balanced.topP,
            Keys.maxTokens: GenerationPreset.balanced.maxTokens,
            Keys.stopSequences: "User:",
            Keys.defaultModelID: ""
        ])
    }
}

struct GenerationPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let temperature: Double
    let topP: Double
    let maxTokens: Int

    static let balanced = GenerationPreset(
        id: "balanced",
        title: "Balanced",
        subtitle: "Good default for small local models",
        temperature: 0.8,
        topP: 0.95,
        maxTokens: 384
    )

    static let precise = GenerationPreset(
        id: "precise",
        title: "Precise",
        subtitle: "More predictable answers",
        temperature: 0.35,
        topP: 0.85,
        maxTokens: 256
    )

    static let creative = GenerationPreset(
        id: "creative",
        title: "Creative",
        subtitle: "More varied responses",
        temperature: 1.05,
        topP: 0.95,
        maxTokens: 512
    )

    static let fast = GenerationPreset(
        id: "fast",
        title: "Fast",
        subtitle: "Shorter responses",
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 192
    )

    static let all: [GenerationPreset] = [.balanced, .precise, .creative, .fast]
}
