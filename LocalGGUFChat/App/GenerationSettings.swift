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
        static let defaultImageModelID = "models.defaultImageModelID"
        static let defaultSpeechToTextModelID = "models.defaultSpeechToTextModelID"
        static let defaultVoiceOutputModelID = "models.defaultVoiceOutputModelID"
        static let generationMode = "generation.mode"
        static let promptStyle = "assistant.promptStyle"
        static let reasoningMode = "assistant.reasoningMode"
        static let reasoningDisplay = "assistant.reasoningDisplay"
        static let liveDisplayMode = "assistant.liveDisplayMode"
        static let typingCharactersPerSecond = "assistant.typingCharactersPerSecond"
        static let globalSystemMessage = "assistant.globalSystemMessage"
        static let smallModelProtection = "assistant.smallModelProtection"
        static let largeModelSurvivalMode = "assistant.largeModelSurvivalMode"
        static let imageGenerationEnabledByDefault = "imageGeneration.enabledByDefault"
        static let imageSize = "imageGeneration.size"
        static let imageQuality = "imageGeneration.quality"
        static let voiceInputMode = "voice.inputMode"
        static let voiceOutputMode = "voice.outputMode"
        static let fileHandlingMode = "files.handlingMode"
        static let showPromptPreview = "diagnostics.showPromptPreview"
        static let detailedErrors = "diagnostics.detailedErrors"
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

    var defaultImageModelID: String {
        get { defaults.string(forKey: Keys.defaultImageModelID) ?? "" }
        set { set(newValue, forKey: Keys.defaultImageModelID) }
    }

    var defaultSpeechToTextModelID: String {
        get { defaults.string(forKey: Keys.defaultSpeechToTextModelID) ?? "" }
        set { set(newValue, forKey: Keys.defaultSpeechToTextModelID) }
    }

    var defaultVoiceOutputModelID: String {
        get { defaults.string(forKey: Keys.defaultVoiceOutputModelID) ?? "" }
        set { set(newValue, forKey: Keys.defaultVoiceOutputModelID) }
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

    var smallModelProtection: Bool {
        get { defaults.bool(forKey: Keys.smallModelProtection) }
        set { set(newValue, forKey: Keys.smallModelProtection) }
    }

    var largeModelSurvivalMode: Bool {
        get { defaults.bool(forKey: Keys.largeModelSurvivalMode) }
        set { set(newValue, forKey: Keys.largeModelSurvivalMode) }
    }

    var imageGenerationEnabledByDefault: Bool {
        get { defaults.bool(forKey: Keys.imageGenerationEnabledByDefault) }
        set { set(newValue, forKey: Keys.imageGenerationEnabledByDefault) }
    }

    var imageSize: ImageGenerationSize {
        get { ImageGenerationSize(rawValue: defaults.string(forKey: Keys.imageSize) ?? "") ?? .square512 }
        set { set(newValue.rawValue, forKey: Keys.imageSize) }
    }

    var imageQuality: ImageGenerationQuality {
        get { ImageGenerationQuality(rawValue: defaults.string(forKey: Keys.imageQuality) ?? "") ?? .balanced }
        set { set(newValue.rawValue, forKey: Keys.imageQuality) }
    }

    var voiceInputMode: VoiceInputMode {
        get { VoiceInputMode(rawValue: defaults.string(forKey: Keys.voiceInputMode) ?? "") ?? .system }
        set { set(newValue.rawValue, forKey: Keys.voiceInputMode) }
    }

    var voiceOutputMode: VoiceOutputMode {
        get { VoiceOutputMode(rawValue: defaults.string(forKey: Keys.voiceOutputMode) ?? "") ?? .off }
        set { set(newValue.rawValue, forKey: Keys.voiceOutputMode) }
    }

    var fileHandlingMode: FileHandlingMode {
        get { FileHandlingMode(rawValue: defaults.string(forKey: Keys.fileHandlingMode) ?? "") ?? .auto }
        set { set(newValue.rawValue, forKey: Keys.fileHandlingMode) }
    }

    var showPromptPreview: Bool {
        get { defaults.bool(forKey: Keys.showPromptPreview) }
        set { set(newValue, forKey: Keys.showPromptPreview) }
    }

    var detailedErrors: Bool {
        get { defaults.bool(forKey: Keys.detailedErrors) }
        set { set(newValue, forKey: Keys.detailedErrors) }
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
        let protectedSmallModel = smallModelProtection && profile.kind == .small
        let survivalModel = largeModelSurvivalMode && (profile.kind == .large || profile.kind == .veryLarge)
        let resolvedPromptStyle = protectedSmallModel ? .plain : promptStyle.resolved(for: profile)
        let resolvedReasoningMode = protectedSmallModel ? .off : reasoningMode.resolved(for: profile)

        if generationMode == .manual, !protectedSmallModel, !survivalModel {
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

        let maxTokensOverride = survivalModel ? min(profile.maxTokens, 96) : profile.maxTokens
        let historyLimitOverride = protectedSmallModel || survivalModel ? 1 : profile.historyLimit
        let promptLimitOverride = protectedSmallModel ? min(profile.promptCharacterLimit, 500) : (survivalModel ? min(profile.promptCharacterLimit, 800) : profile.promptCharacterLimit)

        return EffectiveGenerationSettings(
            profile: profile,
            config: GenerationConfig(
                maxTokens: maxTokensOverride,
                temperature: protectedSmallModel ? 0.55 : profile.temperature,
                topP: protectedSmallModel ? 0.85 : profile.topP,
                stop: stopSequences
            ),
            promptStyle: resolvedPromptStyle,
            reasoningMode: resolvedReasoningMode,
            reasoningDisplay: reasoningDisplay,
            historyLimit: historyLimitOverride,
            promptCharacterLimit: promptLimitOverride
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
        smallModelProtection = true
        largeModelSurvivalMode = false
        imageGenerationEnabledByDefault = false
        imageSize = .square512
        imageQuality = .balanced
        voiceInputMode = .system
        voiceOutputMode = .off
        fileHandlingMode = .auto
        showPromptPreview = false
        detailedErrors = true
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
            Keys.defaultImageModelID: "",
            Keys.defaultSpeechToTextModelID: "",
            Keys.defaultVoiceOutputModelID: "",
            Keys.generationMode: GenerationMode.auto.rawValue,
            Keys.promptStyle: PromptStyle.auto.rawValue,
            Keys.reasoningMode: ReasoningMode.auto.rawValue,
            Keys.reasoningDisplay: ReasoningDisplayMode.hidden.rawValue,
            Keys.liveDisplayMode: LiveDisplayMode.smoothLive.rawValue,
            Keys.typingCharactersPerSecond: 90,
            Keys.globalSystemMessage: Self.defaultSystemMessage,
            Keys.smallModelProtection: true,
            Keys.largeModelSurvivalMode: false,
            Keys.imageGenerationEnabledByDefault: false,
            Keys.imageSize: ImageGenerationSize.square512.rawValue,
            Keys.imageQuality: ImageGenerationQuality.balanced.rawValue,
            Keys.voiceInputMode: VoiceInputMode.system.rawValue,
            Keys.voiceOutputMode: VoiceOutputMode.off.rawValue,
            Keys.fileHandlingMode: FileHandlingMode.auto.rawValue,
            Keys.showPromptPreview: false,
            Keys.detailedErrors: true
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
    case plain
    case raw
    case simple
    case instruct

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .plain: return "Plain"
        case .raw: return "Raw"
        case .simple: return "Simple"
        case .instruct: return "Instruct"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "Uses the safest style for the selected model size."
        case .plain: return "Sends only the latest message. Best for tiny models."
        case .raw: return "Minimal message with no chat template."
        case .simple: return "Short instruction prompt with no chat transcript labels."
        case .instruct: return "Instruction format for stronger instruct-tuned models."
        }
    }

    func resolved(for profile: GenerationProfile) -> PromptStyle {
        guard self == .auto else { return self }
        switch profile.kind {
        case .small: return .plain
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
        case .small: return .off
        case .medium: return .fast
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

enum ImageGenerationSize: String, CaseIterable, Identifiable, Hashable, Sendable {
    case square512
    case square768
    case portrait
    case landscape

    var id: String { rawValue }
    var title: String {
        switch self {
        case .square512: return "512 × 512"
        case .square768: return "768 × 768"
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }
}

enum ImageGenerationQuality: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fast
    case balanced
    case high

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .high: return "High"
        }
    }
}

enum VoiceInputMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case off
    case system
    case localModel

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .system: return "System Speech"
        case .localModel: return "Local Model"
        }
    }
}

enum VoiceOutputMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case off
    case manual
    case autoRead

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .manual: return "Manual"
        case .autoRead: return "Auto-read Replies"
        }
    }
}

enum FileHandlingMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case summarizeFirst
    case useFullIfSmall
    case askForLarge

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .summarizeFirst: return "Summarize First"
        case .useFullIfSmall: return "Use Full Text if Small"
        case .askForLarge: return "Ask Before Large Files"
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
                subtitle: "Plain prompts, short replies, latest message only.",
                maxTokens: 96,
                temperature: 0.55,
                topP: 0.85,
                historyLimit: 1,
                promptCharacterLimit: 500,
                manualHistoryLimit: 2,
                manualPromptCharacterLimit: 800
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
                subtitle: "More context and longer answers, but may be memory heavy.",
                maxTokens: 320,
                temperature: 0.75,
                topP: 0.92,
                historyLimit: 6,
                promptCharacterLimit: 3_000,
                manualHistoryLimit: 8,
                manualPromptCharacterLimit: 4_000
            )
        }

        return GenerationProfile(
            kind: .veryLarge,
            title: "Very Large Model",
            subtitle: "Conservative defaults to reduce memory pressure.",
            maxTokens: 128,
            temperature: 0.65,
            topP: 0.9,
            historyLimit: 1,
            promptCharacterLimit: 900,
            manualHistoryLimit: 3,
            manualPromptCharacterLimit: 1_500
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
