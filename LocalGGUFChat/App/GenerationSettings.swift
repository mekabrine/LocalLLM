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
        static let textModelBehavior = "assistant.textModelBehavior"
        static let responseLength = "assistant.responseLength"
        static let conversationMemory = "assistant.conversationMemory"
        static let speedMode = "assistant.speedMode"
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

    var temperature: Double { get { defaults.double(forKey: Keys.temperature) } set { set(newValue, forKey: Keys.temperature) } }
    var topP: Double { get { defaults.double(forKey: Keys.topP) } set { set(newValue, forKey: Keys.topP) } }
    var maxTokens: Int { get { defaults.integer(forKey: Keys.maxTokens) } set { set(newValue, forKey: Keys.maxTokens) } }
    var stopSequencesText: String { get { defaults.string(forKey: Keys.stopSequences) ?? "" } set { set(newValue, forKey: Keys.stopSequences) } }
    var defaultModelID: String { get { defaults.string(forKey: Keys.defaultModelID) ?? "" } set { set(newValue, forKey: Keys.defaultModelID) } }
    var defaultImageModelID: String { get { defaults.string(forKey: Keys.defaultImageModelID) ?? "" } set { set(newValue, forKey: Keys.defaultImageModelID) } }
    var defaultSpeechToTextModelID: String { get { defaults.string(forKey: Keys.defaultSpeechToTextModelID) ?? "" } set { set(newValue, forKey: Keys.defaultSpeechToTextModelID) } }
    var defaultVoiceOutputModelID: String { get { defaults.string(forKey: Keys.defaultVoiceOutputModelID) ?? "" } set { set(newValue, forKey: Keys.defaultVoiceOutputModelID) } }

    var generationMode: GenerationMode { get { GenerationMode(rawValue: defaults.string(forKey: Keys.generationMode) ?? "") ?? .auto } set { set(newValue.rawValue, forKey: Keys.generationMode) } }
    var promptStyle: PromptStyle { get { PromptStyle(rawValue: defaults.string(forKey: Keys.promptStyle) ?? "") ?? .auto } set { set(newValue.rawValue, forKey: Keys.promptStyle) } }
    var textModelBehavior: TextModelBehavior { get { TextModelBehavior(rawValue: defaults.string(forKey: Keys.textModelBehavior) ?? "") ?? .auto } set { set(newValue.rawValue, forKey: Keys.textModelBehavior) } }
    var responseLength: SimpleResponseLength { get { SimpleResponseLength(rawValue: defaults.string(forKey: Keys.responseLength) ?? "") ?? .normal } set { set(newValue.rawValue, forKey: Keys.responseLength) } }
    var conversationMemory: ConversationMemoryMode { get { ConversationMemoryMode(rawValue: defaults.string(forKey: Keys.conversationMemory) ?? "") ?? .normal } set { set(newValue.rawValue, forKey: Keys.conversationMemory) } }
    var speedMode: AISpeedMode { get { AISpeedMode(rawValue: defaults.string(forKey: Keys.speedMode) ?? "") ?? .balanced } set { set(newValue.rawValue, forKey: Keys.speedMode) } }
    var reasoningMode: ReasoningMode { get { ReasoningMode(rawValue: defaults.string(forKey: Keys.reasoningMode) ?? "") ?? .off } set { set(newValue.rawValue, forKey: Keys.reasoningMode) } }
    var reasoningDisplay: ReasoningDisplayMode { get { ReasoningDisplayMode(rawValue: defaults.string(forKey: Keys.reasoningDisplay) ?? "") ?? .hidden } set { set(newValue.rawValue, forKey: Keys.reasoningDisplay) } }
    var liveDisplayMode: LiveDisplayMode { get { LiveDisplayMode(rawValue: defaults.string(forKey: Keys.liveDisplayMode) ?? "") ?? .smoothLive } set { set(newValue.rawValue, forKey: Keys.liveDisplayMode) } }
    var typingCharactersPerSecond: Int { get { let value = defaults.integer(forKey: Keys.typingCharactersPerSecond); return value == 0 ? 90 : value } set { set(max(30, min(newValue, 180)), forKey: Keys.typingCharactersPerSecond) } }
    var globalSystemMessage: String { get { defaults.string(forKey: Keys.globalSystemMessage) ?? Self.defaultSystemMessage } set { set(newValue, forKey: Keys.globalSystemMessage) } }
    var smallModelProtection: Bool { get { defaults.bool(forKey: Keys.smallModelProtection) } set { set(newValue, forKey: Keys.smallModelProtection) } }
    var largeModelSurvivalMode: Bool { get { defaults.bool(forKey: Keys.largeModelSurvivalMode) } set { set(newValue, forKey: Keys.largeModelSurvivalMode) } }
    var imageGenerationEnabledByDefault: Bool { get { defaults.bool(forKey: Keys.imageGenerationEnabledByDefault) } set { set(newValue, forKey: Keys.imageGenerationEnabledByDefault) } }
    var imageSize: ImageGenerationSize { get { ImageGenerationSize(rawValue: defaults.string(forKey: Keys.imageSize) ?? "") ?? .square512 } set { set(newValue.rawValue, forKey: Keys.imageSize) } }
    var imageQuality: ImageGenerationQuality { get { ImageGenerationQuality(rawValue: defaults.string(forKey: Keys.imageQuality) ?? "") ?? .balanced } set { set(newValue.rawValue, forKey: Keys.imageQuality) } }
    var voiceInputMode: VoiceInputMode { get { VoiceInputMode(rawValue: defaults.string(forKey: Keys.voiceInputMode) ?? "") ?? .system } set { set(newValue.rawValue, forKey: Keys.voiceInputMode) } }
    var voiceOutputMode: VoiceOutputMode { get { VoiceOutputMode(rawValue: defaults.string(forKey: Keys.voiceOutputMode) ?? "") ?? .off } set { set(newValue.rawValue, forKey: Keys.voiceOutputMode) } }
    var fileHandlingMode: FileHandlingMode { get { FileHandlingMode(rawValue: defaults.string(forKey: Keys.fileHandlingMode) ?? "") ?? .auto } set { set(newValue.rawValue, forKey: Keys.fileHandlingMode) } }
    var showPromptPreview: Bool { get { defaults.bool(forKey: Keys.showPromptPreview) } set { set(newValue, forKey: Keys.showPromptPreview) } }
    var detailedErrors: Bool { get { defaults.bool(forKey: Keys.detailedErrors) } set { set(newValue, forKey: Keys.detailedErrors) } }

    var stopSequences: [String] {
        let custom = stopSequencesText.split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(custom + UniversalPromptTemplate.stopSequences))
    }

    var generationConfig: GenerationConfig { GenerationConfig(maxTokens: maxTokens, temperature: temperature, topP: topP, stop: stopSequences) }

    func effectiveSettings(forModelSize fileSize: Int64) -> EffectiveGenerationSettings {
        let profile = GenerationProfile.profile(forFileSize: fileSize)
        let survivalModel = largeModelSurvivalMode && (profile.kind == .large || profile.kind == .veryLarge)
        let behavior = textModelBehavior.resolved(for: profile, smallModelProtection: false)
        let resolvedPromptStyle: PromptStyle = promptStyle == .raw ? .raw : .simple
        let resolvedReasoningMode: ReasoningMode = generationMode == .manual ? reasoningMode : .off

        if generationMode == .manual, !survivalModel {
            return EffectiveGenerationSettings(
                profile: profile,
                config: generationConfig,
                promptStyle: resolvedPromptStyle,
                textModelBehavior: behavior,
                reasoningMode: resolvedReasoningMode,
                reasoningDisplay: reasoningDisplay,
                historyLimit: conversationMemory.historyLimit(for: profile, manual: true),
                promptCharacterLimit: conversationMemory.promptLimit(for: profile, manual: true),
                usesSmallModelProtection: false
            )
        }

        let maxTokensOverride = survivalModel ? min(responseLength.maxTokens(for: profile), 96) : responseLength.maxTokens(for: profile)
        let historyLimitOverride = survivalModel ? min(conversationMemory.historyLimit(for: profile, manual: false), 2) : conversationMemory.historyLimit(for: profile, manual: false)
        let promptLimitOverride = survivalModel ? min(conversationMemory.promptLimit(for: profile, manual: false), 800) : conversationMemory.promptLimit(for: profile, manual: false)

        return EffectiveGenerationSettings(
            profile: profile,
            config: GenerationConfig(maxTokens: maxTokensOverride, temperature: speedMode.temperature(for: profile), topP: speedMode.topP(for: profile), stop: stopSequences),
            promptStyle: resolvedPromptStyle,
            textModelBehavior: behavior,
            reasoningMode: resolvedReasoningMode,
            reasoningDisplay: reasoningDisplay,
            historyLimit: historyLimitOverride,
            promptCharacterLimit: promptLimitOverride,
            usesSmallModelProtection: false
        )
    }

    func previewSettings(profile: GenerationProfile, promptStyle: PromptStyle) -> EffectiveGenerationSettings {
        EffectiveGenerationSettings(
            profile: profile,
            config: GenerationConfig(maxTokens: responseLength.maxTokens(for: profile), temperature: speedMode.temperature(for: profile), topP: speedMode.topP(for: profile), stop: stopSequences),
            promptStyle: promptStyle == .raw ? .raw : .simple,
            textModelBehavior: textModelBehavior.resolved(for: profile, smallModelProtection: false),
            reasoningMode: generationMode == .manual ? reasoningMode : .off,
            reasoningDisplay: reasoningDisplay,
            historyLimit: conversationMemory.historyLimit(for: profile, manual: generationMode == .manual),
            promptCharacterLimit: conversationMemory.promptLimit(for: profile, manual: generationMode == .manual),
            usesSmallModelProtection: false
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
        textModelBehavior = .auto
        responseLength = .normal
        conversationMemory = .normal
        speedMode = .balanced
        reasoningMode = .off
        reasoningDisplay = .hidden
        liveDisplayMode = .smoothLive
        typingCharactersPerSecond = 90
        temperature = GenerationPreset.balanced.temperature
        topP = GenerationPreset.balanced.topP
        maxTokens = GenerationPreset.balanced.maxTokens
        stopSequencesText = ""
        globalSystemMessage = Self.defaultSystemMessage
        smallModelProtection = false
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
        return base + "\n\n" + chat
    }

    private func set<T>(_ value: T, forKey key: String) {
        defaults.set(value, forKey: key)
        objectWillChange.send()
    }

    private func chatInstructionKey(_ id: UUID) -> String { "assistant.chatInstructions.\(id.uuidString)" }

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
            Keys.textModelBehavior: TextModelBehavior.auto.rawValue,
            Keys.responseLength: SimpleResponseLength.normal.rawValue,
            Keys.conversationMemory: ConversationMemoryMode.normal.rawValue,
            Keys.speedMode: AISpeedMode.balanced.rawValue,
            Keys.reasoningMode: ReasoningMode.off.rawValue,
            Keys.reasoningDisplay: ReasoningDisplayMode.hidden.rawValue,
            Keys.liveDisplayMode: LiveDisplayMode.smoothLive.rawValue,
            Keys.typingCharactersPerSecond: 90,
            Keys.globalSystemMessage: Self.defaultSystemMessage,
            Keys.smallModelProtection: false,
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

    static let defaultSystemMessage = "Be helpful, direct, and concise. Reply only to the latest user message."
}

enum SimpleResponseLength: String, CaseIterable, Identifiable, Hashable, Sendable {
    case short
    case normal
    case long
    var id: String { rawValue }
    var title: String { self == .short ? "Short" : self == .normal ? "Normal" : "Long" }
    func maxTokens(for profile: GenerationProfile) -> Int {
        switch self {
        case .short: return min(profile.maxTokens, 96)
        case .normal: return profile.maxTokens
        case .long: return min(max(profile.maxTokens * 2, 192), 768)
        }
    }
}

enum ConversationMemoryMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case off
    case normal
    case more
    var id: String { rawValue }
    var title: String { self == .off ? "Off" : self == .normal ? "Normal" : "More" }
    func historyLimit(for profile: GenerationProfile, manual: Bool) -> Int {
        switch self {
        case .off: return 1
        case .normal: return manual ? profile.manualHistoryLimit : profile.historyLimit
        case .more: return min(max((manual ? profile.manualHistoryLimit : profile.historyLimit) + 4, 8), 16)
        }
    }
    func promptLimit(for profile: GenerationProfile, manual: Bool) -> Int {
        switch self {
        case .off: return min(manual ? profile.manualPromptCharacterLimit : profile.promptCharacterLimit, 1_200)
        case .normal: return manual ? profile.manualPromptCharacterLimit : profile.promptCharacterLimit
        case .more: return min(max((manual ? profile.manualPromptCharacterLimit : profile.promptCharacterLimit) + 1_600, 2_400), 6_000)
        }
    }
}

enum AISpeedMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case battery
    case balanced
    case fast
    var id: String { rawValue }
    var title: String { self == .battery ? "Battery" : self == .balanced ? "Balanced" : "Fast" }
    func temperature(for profile: GenerationProfile) -> Double {
        switch self {
        case .battery: return min(profile.temperature, 0.6)
        case .balanced: return profile.temperature
        case .fast: return min(profile.temperature, 0.7)
        }
    }
    func topP(for profile: GenerationProfile) -> Double {
        switch self {
        case .battery: return min(profile.topP, 0.85)
        case .balanced: return profile.topP
        case .fast: return min(profile.topP, 0.9)
        }
    }
}

enum GenerationMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case manual
    var id: String { rawValue }
    var title: String { self == .auto ? "Simple" : "Advanced" }
    var subtitle: String { self == .auto ? "Uses one safe prompt and simple controls." : "Shows manual sampling and debug options." }
}

enum TextModelBehavior: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case chatInstruct
    case baseCompletion
    var id: String { rawValue }
    var title: String { self == .auto ? "Auto" : self == .chatInstruct ? "Chat/Instruct" : "Base Completion" }
    var subtitle: String { self == .auto ? "Let LocalLLM choose the safest model behavior." : self == .chatInstruct ? "For models trained to follow instructions." : "For base/tiny models that try to continue text." }
    func resolved(for profile: GenerationProfile, smallModelProtection: Bool) -> TextModelBehavior {
        guard self == .auto else { return self }
        return profile.kind == .small ? .baseCompletion : .chatInstruct
    }
}

enum PromptStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case plain
    case raw
    case simple
    case instruct
    var id: String { rawValue }
    var title: String { self == .raw ? "Raw Debug" : "Universal" }
    var subtitle: String { self == .raw ? "Sends exactly the latest user text. Debug only." : "Uses LocalLLM's single safe prompt structure." }
    func resolved(for profile: GenerationProfile) -> PromptStyle { self == .raw ? .raw : .simple }
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
    var subtitle: String { self == .off || self == .auto ? "Direct replies only." : "Advanced instruction hint." }
    func resolved(for profile: GenerationProfile) -> ReasoningMode { self == .auto ? .off : self }
}

enum ReasoningDisplayMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hidden
    case summary
    case full
    var id: String { rawValue }
    var title: String { self == .hidden ? "Hidden" : self == .summary ? "Summary" : "Full" }
}

enum LiveDisplayMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case smoothLive
    case rawStream
    case instant
    var id: String { rawValue }
    var title: String { self == .smoothLive ? "Smooth Live" : self == .rawStream ? "Raw Stream" : "Instant" }
    var subtitle: String { self == .smoothLive ? "Streams live, then reveals chunks smoothly." : self == .rawStream ? "Shows chunks exactly as emitted." : "Shows the full answer when finished." }
}

enum ImageGenerationSize: String, CaseIterable, Identifiable, Hashable, Sendable {
    case square512
    case square768
    case portrait
    case landscape
    var id: String { rawValue }
    var title: String { self == .square512 ? "512 × 512" : self == .square768 ? "768 × 768" : self == .portrait ? "Portrait" : "Landscape" }
}

enum ImageGenerationQuality: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fast
    case balanced
    case high
    var id: String { rawValue }
    var title: String { self == .fast ? "Fast" : self == .balanced ? "Balanced" : "High" }
}

enum VoiceInputMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case off
    case system
    case localModel
    var id: String { rawValue }
    var title: String { self == .off ? "Off" : self == .system ? "System Speech" : "Local Model" }
}

enum VoiceOutputMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case off
    case manual
    case autoRead
    var id: String { rawValue }
    var title: String { self == .off ? "Off" : self == .manual ? "Manual" : "Auto-read Replies" }
}

enum FileHandlingMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case summarizeFirst
    case useFullIfSmall
    case askForLarge
    var id: String { rawValue }
    var title: String { self == .auto ? "Auto" : self == .summarizeFirst ? "Summarize First" : self == .useFullIfSmall ? "Use Full Text if Small" : "Ask Before Large Files" }
}

struct EffectiveGenerationSettings: Sendable {
    let profile: GenerationProfile
    let config: GenerationConfig
    let promptStyle: PromptStyle
    let textModelBehavior: TextModelBehavior
    let reasoningMode: ReasoningMode
    let reasoningDisplay: ReasoningDisplayMode
    let historyLimit: Int
    let promptCharacterLimit: Int
    let usesSmallModelProtection: Bool
}

struct GenerationProfile: Sendable {
    enum Kind: String, Hashable, Sendable { case small, medium, large, veryLarge }
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
            return GenerationProfile(kind: .small, title: "Small Model", subtitle: "Compact memory, short replies, safe prompt.", maxTokens: 96, temperature: 0.55, topP: 0.85, historyLimit: 4, promptCharacterLimit: 1_200, manualHistoryLimit: 6, manualPromptCharacterLimit: 1_600)
        }
        if gb < 4.0 {
            return GenerationProfile(kind: .medium, title: "Medium Model", subtitle: "Balanced context and output length.", maxTokens: 256, temperature: 0.75, topP: 0.92, historyLimit: 6, promptCharacterLimit: 2_400, manualHistoryLimit: 8, manualPromptCharacterLimit: 3_200)
        }
        if gb < 8.0 {
            return GenerationProfile(kind: .large, title: "Large Model", subtitle: "More context and longer answers, but may be memory heavy.", maxTokens: 320, temperature: 0.75, topP: 0.92, historyLimit: 8, promptCharacterLimit: 3_200, manualHistoryLimit: 10, manualPromptCharacterLimit: 4_200)
        }
        return GenerationProfile(kind: .veryLarge, title: "Very Large Model", subtitle: "Conservative defaults to reduce memory pressure.", maxTokens: 128, temperature: 0.65, topP: 0.9, historyLimit: 2, promptCharacterLimit: 1_000, manualHistoryLimit: 4, manualPromptCharacterLimit: 1_600)
    }
}

struct GenerationPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    static let balanced = GenerationPreset(id: "balanced", title: "Balanced", subtitle: "Good default for local models", temperature: 0.8, topP: 0.95, maxTokens: 192)
    static let precise = GenerationPreset(id: "precise", title: "Precise", subtitle: "More predictable answers", temperature: 0.35, topP: 0.85, maxTokens: 128)
    static let creative = GenerationPreset(id: "creative", title: "Creative", subtitle: "More varied responses", temperature: 1.0, topP: 0.95, maxTokens: 256)
    static let fast = GenerationPreset(id: "fast", title: "Fast", subtitle: "Shorter responses", temperature: 0.7, topP: 0.9, maxTokens: 96)
    static let all: [GenerationPreset] = [.balanced, .precise, .creative, .fast]
}
