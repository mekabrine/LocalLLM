import Foundation
import PDFKit
import UniformTypeIdentifiers

enum ModelCapability: String, CaseIterable, Identifiable, Hashable {
    case text
    case imageGeneration
    case speechToText
    case textToSpeech
    case fileHelper
    case vision
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .imageGeneration: return "Image Generation"
        case .speechToText: return "Speech-to-Text"
        case .textToSpeech: return "Text-to-Speech"
        case .fileHelper: return "File Helper"
        case .vision: return "Vision Later"
        case .unknown: return "Unknown"
        }
    }

    var importTitle: String {
        switch self {
        case .text: return "Text Chat"
        case .imageGeneration: return "Image Generation"
        case .speechToText: return "Speech-to-Text"
        case .textToSpeech: return "Text-to-Speech"
        case .fileHelper: return "File Helper"
        case .vision: return "Vision"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.bubble.fill"
        case .imageGeneration: return "photo.fill"
        case .speechToText: return "mic.fill"
        case .textToSpeech: return "speaker.wave.2.fill"
        case .fileHelper: return "doc.text.fill"
        case .vision: return "eye.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var canBeDefault: Bool {
        switch self {
        case .text, .imageGeneration, .speechToText, .textToSpeech:
            return true
        case .fileHelper, .vision, .unknown:
            return false
        }
    }
}

enum ModelPurposeStore {
    private static let prefix = "models.purpose."

    static func purpose(for model: ModelReferenceEntity) -> ModelCapability {
        guard let id = model.id?.uuidString else {
            return ModelCapabilityInfo.inferredPurpose(name: model.displayName)
        }

        if let raw = UserDefaults.standard.string(forKey: prefix + id),
           let purpose = ModelCapability(rawValue: raw) {
            return purpose
        }

        return ModelCapabilityInfo.inferredPurpose(name: model.displayName)
    }

    static func setPurpose(_ purpose: ModelCapability, for model: ModelReferenceEntity) {
        guard let id = model.id?.uuidString else { return }
        UserDefaults.standard.set(purpose.rawValue, forKey: prefix + id)
    }

    static func clearPurpose(for model: ModelReferenceEntity) {
        guard let id = model.id?.uuidString else { return }
        UserDefaults.standard.removeObject(forKey: prefix + id)
    }
}

enum CompatibilityLevel: String, CaseIterable, Identifiable, Hashable {
    case supported
    case likelySupported
    case risky
    case veryHighRisk
    case tooLarge
    case unsupportedArchitecture
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supported: return "Supported"
        case .likelySupported: return "Likely Supported"
        case .risky: return "Risky"
        case .veryHighRisk: return "Very High Risk"
        case .tooLarge: return "Too Large"
        case .unsupportedArchitecture: return "Needs Newer Backend"
        case .unknown: return "Unknown"
        }
    }
}

struct ModelCapabilityInfo {
    let capability: ModelCapability
    let architecture: String
    let quantization: String
    let compatibility: CompatibilityLevel
    let profile: GenerationProfile
    let warning: String?

    static func resolve(for model: ModelReferenceEntity) -> ModelCapabilityInfo {
        infer(name: model.displayName, fileSize: model.fileSize, purposeOverride: ModelPurposeStore.purpose(for: model))
    }

    static func infer(name: String?, fileSize: Int64, purposeOverride: ModelCapability? = nil) -> ModelCapabilityInfo {
        let displayName = (name ?? "").lowercased()
        let profile = GenerationProfile.profile(forFileSize: fileSize)
        let gb = Double(fileSize) / 1_000_000_000
        let capability = purposeOverride ?? inferredPurpose(name: name)
        let backendIssue = ModelBackendCompatibility.blockingIssue(for: name)

        let architecture: String
        if displayName.contains("qwen") { architecture = "Qwen" }
        else if displayName.contains("llama") { architecture = "Llama" }
        else if displayName.contains("mistral") { architecture = "Mistral" }
        else if displayName.contains("gemma") { architecture = "Gemma" }
        else if displayName.contains("phi") { architecture = "Phi" }
        else if displayName.contains("stable") || displayName.contains("sdxl") || displayName.contains("sd1") || displayName.contains("diffusion") { architecture = "Diffusion" }
        else if displayName.contains("flux") { architecture = "Flux" }
        else if displayName.contains("whisper") { architecture = "Whisper" }
        else { architecture = "Unknown" }

        let quantization = Self.extractQuantization(from: displayName)

        let compatibility: CompatibilityLevel
        if backendIssue != nil {
            compatibility = .unsupportedArchitecture
        } else if capability == .imageGeneration || capability == .speechToText || capability == .textToSpeech || capability == .vision {
            compatibility = .unknown
        } else if gb < 1.5 {
            compatibility = .likelySupported
        } else if gb < 4.0 {
            compatibility = .likelySupported
        } else if gb < 7.0 {
            compatibility = .risky
        } else if gb < 10.0 {
            compatibility = .veryHighRisk
        } else {
            compatibility = .tooLarge
        }

        let warning: String?
        switch compatibility {
        case .tooLarge:
            warning = "This model is probably too large to load locally on this device. Use a smaller quantization or remote/server mode."
        case .veryHighRisk:
            warning = "This model may fail during context creation. Try Large Model Survival Mode."
        case .risky:
            warning = "This model may load slowly or fail under memory pressure."
        case .unsupportedArchitecture:
            warning = backendIssue ?? "This model needs a newer or different backend before it can run."
        case .unknown where capability != .unknown:
            warning = "This model is saved as \(capability.title). A dedicated backend is still required before it can run."
        case .unknown:
            warning = "Choose this model's purpose from the model menu."
        default:
            warning = nil
        }

        return ModelCapabilityInfo(
            capability: capability,
            architecture: architecture,
            quantization: quantization,
            compatibility: compatibility,
            profile: profile,
            warning: warning
        )
    }

    static func inferredPurpose(name: String?) -> ModelCapability {
        let displayName = (name ?? "").lowercased()
        if displayName.contains("stable") || displayName.contains("diffusion") || displayName.contains("sdxl") || displayName.contains("sd1") || displayName.contains("flux") || displayName.contains("anime") || displayName.contains("image") {
            return .imageGeneration
        }
        if displayName.contains("whisper") || displayName.contains("speech") || displayName.contains("stt") {
            return .speechToText
        }
        if displayName.contains("piper") || displayName.contains("tts") || displayName.contains("voice") {
            return .textToSpeech
        }
        if displayName.contains("vision") || displayName.contains("llava") || displayName.contains("moondream") {
            return .vision
        }
        return .text
    }

    private static func extractQuantization(from name: String) -> String {
        let normalized = name.replacingOccurrences(of: "-", with: "_")
        let patterns = [
            "q8_k_p", "q8_k", "q8_0",
            "q6_k",
            "q5_k_m", "q5_k_s", "q5_k",
            "q4_k_m", "q4_k_s", "q4_k", "q4_0", "q4_1",
            "q3_k_m", "q3_k_s", "q3_k_l", "q3_k",
            "q2_k",
            "ud_iq2_m", "iq2_m", "iq4_nl", "iq4_xs", "iq3_xs", "iq2_xs"
        ]
        if let match = patterns.first(where: { normalized.contains($0) }) {
            return match.uppercased()
        }
        return "Unknown"
    }
}

struct RuntimeDiagnostic: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let likelyCause: String
    let stage: String
    let rawError: String
    let modelName: String
    let modelSize: String
    let compatibility: String
    let settingsSummary: String

    var shortMessage: String {
        "\(title). Tap for details."
    }

    var copyText: String {
        """
        LocalLLM Diagnostic
        Title: \(title)
        Likely cause: \(likelyCause)
        Stage: \(stage)
        Raw error: \(rawError)
        Model: \(modelName)
        Size: \(modelSize)
        Compatibility: \(compatibility)
        Settings: \(settingsSummary)
        """
    }

    static func from(error: Error, stage: String, model: ModelReferenceEntity?, settings: EffectiveGenerationSettings?) -> RuntimeDiagnostic {
        let info: ModelCapabilityInfo
        if let model {
            info = ModelCapabilityInfo.resolve(for: model)
        } else {
            info = ModelCapabilityInfo.infer(name: nil, fileSize: 0)
        }
        let modelSize = ByteCountFormatter.string(fromByteCount: model?.fileSize ?? 0, countStyle: .file)
        let rawError = String(describing: error)
        let normalizedStage = normalizedStage(rawError: rawError, fallback: stage)
        let likelyCause: String

        if let issue = ModelBackendCompatibility.blockingIssue(for: model?.displayName) {
            likelyCause = issue
        } else {
            switch info.compatibility {
            case .tooLarge, .veryHighRisk:
                likelyCause = "This model is probably too large for this device, failed while allocating memory, or needs a newer backend."
            case .unsupportedArchitecture:
                likelyCause = "The model architecture or quantization is not supported by the current backend."
            case .unknown where info.capability != .text:
                likelyCause = "This model needs a dedicated \(info.capability.title) backend before it can run."
            default:
                likelyCause = "The backend failed while loading or generating. Check the raw error and model compatibility."
            }
        }

        let summary: String
        if let settings {
            summary = "Mode: \(settings.profile.title), Prompt: \(settings.promptStyle.title), Reasoning: \(settings.reasoningMode.title), Max tokens: \(settings.config.maxTokens)"
        } else {
            summary = "Unavailable"
        }

        return RuntimeDiagnostic(
            title: "Model Load Error",
            likelyCause: likelyCause,
            stage: normalizedStage,
            rawError: rawError,
            modelName: model?.displayName ?? "Unknown model",
            modelSize: modelSize,
            compatibility: info.compatibility.title,
            settingsSummary: summary
        )
    }

    private static func normalizedStage(rawError: String, fallback: String) -> String {
        let lower = rawError.lowercased()
        if lower.contains("cannot load model") || lower.contains("load model") {
            return "Loading model backend / creating context"
        }
        if lower.contains("token") {
            return "Tokenizing prompt"
        }
        if lower.contains("memory") || lower.contains("allocation") || lower.contains("alloc") {
            return "Allocating model memory"
        }
        return fallback
    }
}

enum ChatFileAttachmentExtractor {
    static let supportedExtensions: Set<String> = ["txt", "md", "json", "csv", "swift", "py", "js", "html", "css", "xml", "log", "pdf"]
    static let blockedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"]

    static func extractText(from url: URL, maxCharacters: Int = 12_000) throws -> (title: String, text: String, summary: String) {
        let ext = url.pathExtension.lowercased()
        guard !blockedImageExtensions.contains(ext) else {
            throw NSError(domain: "LocalLLM.FileAttachments", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image uploads are coming later with vision model support."])
        }

        guard supportedExtensions.contains(ext) else {
            throw NSError(domain: "LocalLLM.FileAttachments", code: 2, userInfo: [NSLocalizedDescriptionKey: "This file type is not supported yet."])
        }

        let title = url.lastPathComponent
        let rawText: String
        if ext == "pdf" {
            rawText = try extractPDFText(url: url)
        } else {
            rawText = try String(contentsOf: url, encoding: .utf8)
        }

        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(maxCharacters))
        let summary = ext == "pdf" ? "PDF · extracted text" : "\(ext.uppercased()) file · text extracted"
        return (title, limited, summary)
    }

    private static func extractPDFText(url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "LocalLLM.FileAttachments", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read this PDF."])
        }

        var result = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string else { continue }
            result += "\n\nPage \(index + 1):\n\(text)"
        }

        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LocalLLM.FileAttachments", code: 4, userInfo: [NSLocalizedDescriptionKey: "No readable text was found in this PDF."])
        }
        return result
    }
}
