import Foundation
import Combine

@MainActor
final class GenerationSettings: ObservableObject {
    private enum Keys {
        static let temperature = "generation.temperature"
        static let topP = "generation.topP"
        static let maxTokens = "generation.maxTokens"
        static let stopSequences = "generation.stopSequences"
        static let defaultModelID = "models.defaultModelID"
        static let generationMode = "generation.mode"
        static let promptStyle = "assistant.promptStyle"
        static let reasoningMode = "assistant.reasoningMode"
        static let reasoningDisplay = "assistant.reasoningDisplay"
        static let liveDisplayMode = "assistant.liveDisplayMode"
        static let typingCharactersPerSecond = "assistant.typingCharactersPerSecond"
        static let globalSystemMessage = "assistant.globalSystemMessage"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var temperature: Double {
        get { defaults.double(forKey: Keys.temperature) }
        set { set(newValue, forKey: Keys.temperature) }
    }

    var topP: Double {
        get { defaults.double(forKey: Keys.topP) }
        set { set(newValue, forKey: Keys.topP) }
    }

    var maxTokens: Int {
        get { defaults.integer(forKey: Keys.maxTokens) }
        set { set(newValue, forKey: Keys.maxTokens) }
    }

    var stopSequencesText: String {
        get { defaults.string(forKey: Keys.stopSequences) ?? "" }
        set { set(newValue, forKey: Keys.stopSequences) }
    }

    var defaultModelID: String {
        get { defaults.string(forKey: Keys.defaultModelID) ?? "" }
        set { set(newValue, forKey: Keys.defaultModelID) }
    }

    var generationMode: GenerationMode {
        get { GenerationMode(rawValue: defaults.string(forKey: Keys.generationMode) ?? "") ?? .auto }
        set { set(newValue.rawValue, forKey: Keys.generationMode) }
    }

    var promptStyle: PromptStyle {
        get { PromptStyle(rawValue: defaults.string(forKey: Keys.promptStyle) ?? "") ?? .auto }
        set { set(newValue.rawValue, forKey: Keys.promptStyle) }
    }

    var reasoningMode: ReasoningMode {
        get { ReasoningMode(rawValue: defaults.string(forKey: Keys.reasoningMode) ?? "") ?? .auto }
        set { set(newValue.rawValue, forKey: Keys.reasoningMode) }
    }

    var reasoningDisplay: ReasoningDisplayMode {
        get { ReasoningDisplayMode(rawValue: defaults.string(forKey: Keys.reasoningDisplay) ?? "") ?? .hidden }
        set { set(newValue.rawValue, forKey: Keys.reasoningDisplay) }
    }

    var liveDisplayMode: LiveDisplayMode {
        get { LiveDisplayMode(rawValue: defaults.string(forKey: Keys.liveDisplayMode) ?? "") ?? .smoothLive }
        set { set(newValue.rawValue, forKey: Keys.liveDisplayMode) }
    }

    var typingCharactersPerSecond: Int {
        get {
            let value = defaults.integer(forKey: Keys.typingCharactersPerSecond)
            return value == 0 ? 90 : value
        }
        set { set(max(30, min(newValue, 180)), forKey: Keys.typingCharactersPerSecond) }
    }

    var globalSystemMessage: String {
        get { defaults.string(forKey: Keys.globalSystemMessage) ?? Self.defaultSystemMessage }
        set { set(newValue, forKey: Keys.globalSystemMessage) }
    }

    var stopSequences: [String] {
        stopSequencesText
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var generationConfig: GenerationConfig {
        GenerationConfig(maxTokens: maxTokens, temperature: temperature, topP: topP, stop: stopSequences)
    }

    func effectiveSettings(forModelSize fileSize: Int64) -> EffectiveGenerationSettings {
        let profile = GenerationProfile.profile(forFileSize: fileSize)
        let resolvedPromptStyle = promptStyle.resolved(for: profile)
        let resolvedReasoningMode = reasoningMode.resolved(for: profile)

        if generationMode == .manual {
            return EffectiveGenerationSettings(
                profile: profile,
                config: generationConfig,
                promptStyle: resolvedPromptStyle,
                reasoningMode: resolvedReasoningMode,
                reasoningDisplay: reasoningDisplay,
                historyLimit: profile.manualHistoryLimit,
                promptCharacterLimit: profile.manualPromptCharacterLimit
            )
        }

        return EffectiveGenerationSettings(
            profile: profile,
            config: GenerationConfig(
                maxTokens: profile.maxTokens,
                temperature: profile.temperature,
                topP: profile.topP,
                stop: stopSequences
            ),
            promptStyle: resolvedPromptStyle,
            reasoningMode: resolvedReasoningMode,
            reasoningDisplay: reasoningDisplay,
            historyLimit: profile.historyLimit,
            promptCharacterLimit: profile.promptCharacterLimit
        )
    }

    func applyPreset(_ preset: GenerationPreset) {
        generationMode = .manual
        temperature = preset.temperature
        topP = preset.topP
        maxTokens = preset.maxTokens
    }

    func resetSamplingDefaults() {
        generationMode = .auto
        promptStyle = .auto
        reasoningMode = .auto
        reasoningDisplay = .hidden
        liveDisplayMode = .smoothLive
        typingCharactersPerSecond = 90
        temperature = GenerationPreset.balanced.temperature
        topP = GenerationPreset.balanced.topP
        maxTokens = GenerationPreset.balanced.maxTokens
        stopSequencesText = ""
        globalSystemMessage = Self.defaultSystemMessage
    }

    func chatInstructions(for chatID: UUID?) -> String {
        guard let chatID else { return "" }
        return defaults.string(forKey: chatInstructionKey(chatID)) ?? ""
    }

    func setChatInstructions(_ text: String, for chatID: UUID?) {
        guard let chatID else { return }
        set(text, forKey: chatInstructionKey(chatID))
    }

    func combinedSystemMessage(for chatID: UUID?) -> String {
        let base = globalSystemMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = chatInstructions(for: chatID).trimmingCharacters(in: .whitespacesAndNewlines)

        if base.isEmpty { return chat }
        if chat.isEmpty { return base }
        return base + "\n\nChat-specific instructions:\n" + chat
    }

    private func set<T>(_ value: T, forKey key: String) {
        defaults.set(value, forKey: key)
        objectWillChange.send()
    }

    private func chatInstructionKey(_ id: UUID) -> String {
        "assistant.chatInstructions.\(id.uuidString)"
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.temperature: GenerationPreset.balanced.temperature,
            Keys.topP: GenerationPreset.balanced.topP,
            Keys.maxTokens: GenerationPreset.balanced.maxTokens,
            Keys.stopSequences: "",
            Keys.defaultModelID: "",
            Keys.generationMode: GenerationMode.auto.rawValue,
            Keys.promptStyle: PromptStyle.auto.rawValue,
            Keys.reasoningMode: ReasoningMode.auto.rawValue,
            Keys.reasoningDisplay: ReasoningDisplayMode.hidden.rawValue,
            Keys.liveDisplayMode: LiveDisplayMode.smoothLive.rawValue,
            Keys.typingCharactersPerSecond: 90,
            Keys.globalSystemMessage: Self.defaultSystemMessage
        ])
    }

    static let defaultSystemMessage = "Answer only as the assistant. Be direct and helpful. Do not write messages for the user. Do not continue the conversation as a script. Do not output role labels."
}

enum GenerationMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto Recommended"
        case .manual: return "Manual Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "Adjusts prompt length, history, and output size for the selected model."
        case .manual: return "Uses your custom sampling settings."
        }
    }
}

enum PromptStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case raw
    case simple
    case instruct

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .raw: return "Raw"
        case .simple: return "Simple"
        case .instruct: return "Instruct"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "Uses the safest style for the selected model size."
        case .raw: return "Minimal prompt. Best for tiny models that ramble."
        case .simple: return "Short instruction prompt with no chat transcript labels."
        case .instruct: return "Instruction format for stronger instruct-tuned models."
        }
    }

    func resolved(for profile: GenerationProfile) -> PromptStyle {
        guard self == .auto else { return self }
        switch profile.kind {
        case .small: return .raw
        case .medium: return .simple
        case .large, .veryLarge: return .simple
        }
    }
}

enum ReasoningMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case off
    case fast
    case balanced
    case deep

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .off: return "Off"
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .deep: return "Deep"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "Chooses a safe reasoning level for the model size."
        case .off: return "Direct answers only."
        case .fast: return "Briefly checks the answer before responding."
        case .balanced: return "Uses a short internal plan for better answers."
        case .deep: return "More careful answers for larger models."
        }
    }

    func resolved(for profile: GenerationProfile) -> ReasoningMode {
        guard self == .auto else { return self }
        switch profile.kind {
        case .small: return .fast
        case .medium: return .balanced
        case .large, .veryLarge: return .balanced
        }
    }
}

enum ReasoningDisplayMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hidden
    case summary
    case full

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hidden: return "Hidden"
        case .summary: return "Summary"
        case .full: return "Full"
        }
    }
}

enum LiveDisplayMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case smoothLive
    case rawStream
    case instant

    var id: String { rawValue }
    var title: String {
        switch self {
        case .smoothLive: return "Smooth Live"
        case .rawStream: return "Raw Stream"
        case .instant: return "Instant"
        }
    }

    var subtitle: String {
        switch self {
        case .smoothLive: return "Streams live, then reveals chunks smoothly."
        case .rawStream: return "Shows chunks exactly as the model emits them."
        case .instant: return "Shows the full answer when generation finishes."
        }
    }
}

struct EffectiveGenerationSettings: Sendable {
    let profile: GenerationProfile
    let config: GenerationConfig
    let promptStyle: PromptStyle
    let reasoningMode: ReasoningMode
    let reasoningDisplay: ReasoningDisplayMode
    let historyLimit: Int
    let promptCharacterLimit: Int
}

struct GenerationProfile: Sendable {
    enum Kind: String, Hashable, Sendable {
        case small
        case medium
        case large
        case veryLarge
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let historyLimit: Int
    let promptCharacterLimit: Int
    let manualHistoryLimit: Int
    let manualPromptCharacterLimit: Int

    static func profile(forFileSize bytes: Int64) -> GenerationProfile {
        let gb = Double(bytes) / 1_000_000_000

        if gb < 1.5 {
            return GenerationProfile(
                kind: .small,
                title: "Small Model",
                subtitle: "Short replies, minimal prompt, latest context only.",
                maxTokens: 128,
                temperature: 0.7,
                topP: 0.9,
                historyLimit: 2,
                promptCharacterLimit: 900,
                manualHistoryLimit: 4,
                manualPromptCharacterLimit: 1_500
            )
        }

        if gb < 4.0 {
            return GenerationProfile(
                kind: .medium,
                title: "Medium Model",
                subtitle: "Balanced context and output length.",
                maxTokens: 256,
                temperature: 0.75,
                topP: 0.92,
                historyLimit: 4,
                promptCharacterLimit: 2_000,
                manualHistoryLimit: 6,
                manualPromptCharacterLimit: 3_000
            )
        }

        if gb < 8.0 {
            return GenerationProfile(
                kind: .large,
                title: "Large Model",
                subtitle: "More context and longer answers.",
                maxTokens: 384,
                temperature: 0.8,
                topP: 0.95,
                historyLimit: 8,
                promptCharacterLimit: 4_000,
                manualHistoryLimit: 10,
                manualPromptCharacterLimit: 5_000
            )
        }

        return GenerationProfile(
            kind: .veryLarge,
            title: "Very Large Model",
            subtitle: "Conservative defaults to reduce memory pressure.",
            maxTokens: 320,
            temperature: 0.75,
            topP: 0.92,
            historyLimit: 6,
            promptCharacterLimit: 3_000,
            manualHistoryLimit: 8,
            manualPromptCharacterLimit: 4_000
        )
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
        subtitle: "Good default for local models",
        temperature: 0.8,
        topP: 0.95,
        maxTokens: 192
    )

    static let precise = GenerationPreset(
        id: "precise",
        title: "Precise",
        subtitle: "More predictable answers",
        temperature: 0.35,
        topP: 0.85,
        maxTokens: 128
    )

    static let creative = GenerationPreset(
        id: "creative",
        title: "Creative",
        subtitle: "More varied responses",
        temperature: 1.0,
        topP: 0.95,
        maxTokens: 256
    )

    static let fast = GenerationPreset(
        id: "fast",
        title: "Fast",
        subtitle: "Shorter responses",
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 96
    )

    static let all: [GenerationPreset] = [.balanced, .precise, .creative, .fast]
}
