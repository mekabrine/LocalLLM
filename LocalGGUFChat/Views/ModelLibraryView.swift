import SwiftUI
import CoreData
import UIKit

struct ModelLibraryView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var selectedFilter: ModelCapability = .text
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var statusText: String?
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            ZStack {
                StudioTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        capabilityTabs
                        modelGrid
                        if isImporting {
                            Label("Importing model… Keep the app open.", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundColor(StudioTheme.secondaryText)
                        }
                        if let statusText { Text(statusText).font(.caption).foregroundColor(StudioTheme.secondaryText) }
                        if let errorText { Text(errorText).font(.caption).foregroundColor(StudioTheme.danger) }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingImporter = true } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(isImporting)
                }
            }
            .sheet(isPresented: $showingImporter) {
                ModelDocumentPicker(allowsMultipleSelection: true) { result in
                    showingImporter = false
                    importModels(result)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                StudioIconCircle(systemName: "library.fill", color: .accentColor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Library")
                        .font(.largeTitle.weight(.bold))
                    Text("Text, image, voice, files, and future vision models.")
                        .font(.subheadline)
                        .foregroundColor(StudioTheme.secondaryText)
                }
            }
        }
    }

    private var capabilityTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([ModelCapability.text, .imageGeneration, .speechToText, .textToSpeech, .fileHelper, .vision, .unknown]) { capability in
                    Button {
                        selectedFilter = capability
                    } label: {
                        Label(capability.title, systemImage: capability.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selectedFilter == capability ? .white : StudioTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(selectedFilter == capability ? Color.accentColor : StudioTheme.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var modelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            ForEach(filteredModels) { model in
                ModelLibraryCard(model: model)
                    .environmentObject(generationSettings)
            }

            if filteredModels.isEmpty {
                StudioGlassCard(cornerRadius: 24) {
                    VStack(spacing: 12) {
                        StudioIconCircle(systemName: selectedFilter.systemImage, color: StudioTheme.secondaryText, size: 52)
                        Text("No \(selectedFilter.title) models")
                            .font(.headline)
                        Text(emptyStateText)
                            .font(.subheadline)
                            .foregroundColor(StudioTheme.secondaryText)
                            .multilineTextAlignment(.center)
                        Button { showingImporter = true } label: {
                            Label("Import Model", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var filteredModels: [ModelReferenceEntity] {
        let all = Array(models)
        return all.filter { model in
            let info = ModelCapabilityInfo.infer(name: model.displayName, fileSize: model.fileSize)
            if selectedFilter == .fileHelper { return info.capability == .text }
            return info.capability == selectedFilter
        }
    }

    private var emptyStateText: String {
        switch selectedFilter {
        case .imageGeneration: return "Import a compatible diffusion/image model. The UI is ready; a dedicated image backend is still required."
        case .speechToText: return "Import a speech-to-text model such as a Whisper-style model."
        case .textToSpeech: return "Import a local voice/TTS model, or use the system voice option in Settings."
        case .vision: return "Vision models and image uploads are coming later."
        default: return "Import a model to add it to this category."
        }
    }

    private func importModels(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImporting = true
            statusText = nil
            errorText = nil

            Task {
                do {
                    var importedItems: [(bookmark: Data, displayName: String, originalPath: String, fileSize: Int64)] = []
                    for url in urls {
                        let displayName = ModelFileAccess.displayName(for: url)
                        let originalPath = url.path
                        let fileSize = ModelFileAccess.fileSize(at: url)
                        let bookmark = try await ModelFileAccess.makeBookmarkAsync(for: url)
                        importedItems.append((bookmark, displayName, originalPath, fileSize))
                    }

                    await MainActor.run {
                        do {
                            var count = 0
                            for item in importedItems {
                                let model = try PersistenceController.shared.upsertModel(
                                    from: item.bookmark,
                                    displayName: item.displayName,
                                    originalPath: item.originalPath,
                                    fileSize: item.fileSize
                                )
                                setDefaultIfNeeded(model)
                                count += 1
                            }
                            statusText = count == 1 ? "Imported 1 model." : "Imported \(count) models."
                            errorText = nil
                            isImporting = false
                        } catch {
                            errorText = error.localizedDescription
                            isImporting = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        errorText = error.localizedDescription
                        isImporting = false
                    }
                }
            }
        } catch {
            errorText = error.localizedDescription
            isImporting = false
        }
    }

    private func setDefaultIfNeeded(_ model: ModelReferenceEntity) {
        let info = ModelCapabilityInfo.infer(name: model.displayName, fileSize: model.fileSize)
        guard let id = model.id?.uuidString else { return }
        switch info.capability {
        case .text:
            if generationSettings.defaultModelID.isEmpty { generationSettings.defaultModelID = id }
        case .imageGeneration:
            if generationSettings.defaultImageModelID.isEmpty { generationSettings.defaultImageModelID = id }
        case .speechToText:
            if generationSettings.defaultSpeechToTextModelID.isEmpty { generationSettings.defaultSpeechToTextModelID = id }
        case .textToSpeech:
            if generationSettings.defaultVoiceOutputModelID.isEmpty { generationSettings.defaultVoiceOutputModelID = id }
        default:
            break
        }
    }
}

private struct ModelLibraryCard: View {
    @EnvironmentObject private var generationSettings: GenerationSettings
    @ObservedObject var model: ModelReferenceEntity

    private var info: ModelCapabilityInfo {
        ModelCapabilityInfo.infer(name: model.displayName, fileSize: model.fileSize)
    }

    var body: some View {
        StudioGlassCard(cornerRadius: 22, borderColor: borderColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    StudioIconCircle(systemName: info.capability.systemImage, color: badgeColor)
                    Spacer()
                    Menu {
                        Button("Set as Default Chat Model") { setDefault(.text) }
                        Button("Set as Default Image Model") { setDefault(.imageGeneration) }
                        Button("Set as Default Speech-to-Text") { setDefault(.speechToText) }
                        Button("Set as Default Voice Output") { setDefault(.textToSpeech) }
                        Button("Copy Diagnostics") { UIPasteboard.general.string = diagnostics }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(StudioTheme.secondaryText)
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.displayName ?? "Model")
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)) • \(info.architecture) • \(info.quantization)")
                        .font(.caption)
                        .foregroundColor(StudioTheme.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    StudioBadge(title: info.capability.title, color: .accentColor)
                    StudioBadge(title: info.compatibility.title, color: badgeColor)
                }

                if let warning = info.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(badgeColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isAnyDefault {
                    Label(defaultText, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(StudioTheme.success)
                }
            }
        }
    }

    private var badgeColor: Color {
        switch info.compatibility {
        case .supported, .likelySupported: return StudioTheme.success
        case .risky, .veryHighRisk: return StudioTheme.warning
        case .tooLarge, .unsupportedArchitecture: return StudioTheme.danger
        case .unknown: return StudioTheme.secondaryText
        }
    }

    private var borderColor: Color {
        switch info.compatibility {
        case .tooLarge, .unsupportedArchitecture: return StudioTheme.danger.opacity(0.35)
        case .veryHighRisk, .risky: return StudioTheme.warning.opacity(0.35)
        default: return StudioTheme.border
        }
    }

    private var isAnyDefault: Bool {
        let id = model.id?.uuidString ?? ""
        return generationSettings.defaultModelID == id ||
        generationSettings.defaultImageModelID == id ||
        generationSettings.defaultSpeechToTextModelID == id ||
        generationSettings.defaultVoiceOutputModelID == id
    }

    private var defaultText: String {
        let id = model.id?.uuidString ?? ""
        if generationSettings.defaultModelID == id { return "Default Chat" }
        if generationSettings.defaultImageModelID == id { return "Default Image" }
        if generationSettings.defaultSpeechToTextModelID == id { return "Default Speech" }
        if generationSettings.defaultVoiceOutputModelID == id { return "Default Voice" }
        return "Default"
    }

    private var diagnostics: String {
        """
        Model: \(model.displayName ?? "Unknown")
        Size: \(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
        Capability: \(info.capability.title)
        Architecture: \(info.architecture)
        Quantization: \(info.quantization)
        Compatibility: \(info.compatibility.title)
        Path: \(model.originalPath ?? "Unknown")
        """
    }

    private func setDefault(_ capability: ModelCapability) {
        guard let id = model.id?.uuidString else { return }
        switch capability {
        case .text: generationSettings.defaultModelID = id
        case .imageGeneration: generationSettings.defaultImageModelID = id
        case .speechToText: generationSettings.defaultSpeechToTextModelID = id
        case .textToSpeech: generationSettings.defaultVoiceOutputModelID = id
        default: break
        }
    }
}
