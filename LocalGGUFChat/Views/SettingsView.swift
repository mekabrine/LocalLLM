import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings
    @AppStorage("onboarding.hasCompleted") private var hasCompletedOnboarding = true

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var showingImporter = false
    @State private var showingModelLibrary = false
    @State private var showingPromptPreview = false
    @State private var isImporting = false
    @State private var importStatus: String?
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                introSection
                aiSection
                modelDefaultsSection
                fileSection
                backendSection
                advancedSection
                diagnosticsSection
                onboardingSection
                aboutSection
                statusSections
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isImporting)
                }
            }
            .onAppear { ensureVisibleModelsFolderExists() }
            .sheet(isPresented: $showingImporter) {
                ModelDocumentPicker(allowsMultipleSelection: true) { result in
                    showingImporter = false
                    importModels(result)
                }
            }
            .sheet(isPresented: $showingModelLibrary) {
                ModelLibraryView()
                    .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
                    .environmentObject(generationSettings)
            }
            .sheet(isPresented: $showingPromptPreview) {
                PromptPreviewView()
                    .environmentObject(generationSettings)
            }
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("LocalLLM", systemImage: "sparkles")
                    .font(.title2.weight(.bold))
                Text("Simple private AI chat with local GGUF models. Advanced controls are collapsed so the app has one main AI path.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var aiSection: some View {
        Section(header: Text("AI"), footer: Text("LocalLLM now uses one universal prompt structure with built-in start/stop guards. Advanced prompt styles are hidden unless you open Advanced.")) {
            Picker("Mode", selection: $generationSettings.generationMode) {
                ForEach(GenerationMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)

            Picker("Response Length", selection: $generationSettings.responseLength) {
                ForEach(SimpleResponseLength.allCases) { length in Text(length.title).tag(length) }
            }

            Picker("Memory", selection: $generationSettings.conversationMemory) {
                ForEach(ConversationMemoryMode.allCases) { mode in Text(mode.title).tag(mode) }
            }

            Picker("Speed", selection: $generationSettings.speedMode) {
                ForEach(AISpeedMode.allCases) { mode in Text(mode.title).tag(mode) }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("System Message")
                TextEditor(text: $generationSettings.globalSystemMessage)
                    .frame(minHeight: 82)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }

            Button("Reset AI Defaults") { generationSettings.resetSamplingDefaults() }
        }
    }

    private var modelDefaultsSection: some View {
        Section(header: Text("Models"), footer: Text("Imported local files are copied into LocalLLM/Models by default to avoid permission-loss errors.")) {
            Picker("Chat Model", selection: $generationSettings.defaultModelID) {
                Text("None").tag("")
                ForEach(modelsMatching(.text)) { model in Text(model.displayName ?? "Model").tag(model.id?.uuidString ?? "") }
            }
            Picker("Image Model", selection: $generationSettings.defaultImageModelID) {
                Text("None").tag("")
                ForEach(modelsMatching(.imageGeneration)) { model in Text(model.displayName ?? "Image Model").tag(model.id?.uuidString ?? "") }
            }
            Button { showingModelLibrary = true } label: { Label("Manage Models", systemImage: "library.fill") }
            Button { showingImporter = true } label: { Label("Import Local GGUF", systemImage: "square.and.arrow.down") }
                .disabled(isImporting)
            Button { scanVisibleModelsFolder() } label: { Label("Scan LocalLLM/Models", systemImage: "folder.badge.gearshape") }
                .disabled(isImporting)
        }
    }

    private var fileSection: some View {
        Section(header: Text("Files"), footer: Text("Text, code, CSV, JSON, Markdown, and PDFs can be attached to chats.")) {
            Picker("File Handling", selection: $generationSettings.fileHandlingMode) {
                ForEach(FileHandlingMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Label("Supported: TXT, MD, JSON, CSV, PDF, Swift, Python, JS, HTML, CSS, logs", systemImage: "doc.text")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var backendSection: some View {
        Section(header: Text("Backends"), footer: Text("Text chat runs through the local GGUF backend. Image, speech, voice, and vision models can be saved and organized, but need dedicated runtime backends before they can run.")) {
            Label("Text GGUF: installed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
            Label("Image generation: backend not installed", systemImage: "photo")
                .foregroundColor(.orange)
            Label("Speech and voice: backend not installed", systemImage: "waveform")
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section(header: Text("Advanced")) {
            DisclosureGroup("Manual generation") {
                ForEach(GenerationPreset.all) { preset in
                    Button { generationSettings.applyPreset(preset) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.title)
                                Text(preset.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(preset.maxTokens)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading) {
                    HStack { Text("Temperature"); Spacer(); Text(generationSettings.temperature, format: .number.precision(.fractionLength(2))).foregroundColor(.secondary) }
                    Slider(value: $generationSettings.temperature, in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading) {
                    HStack { Text("Top P"); Spacer(); Text(generationSettings.topP, format: .number.precision(.fractionLength(2))).foregroundColor(.secondary) }
                    Slider(value: $generationSettings.topP, in: 0.05...1, step: 0.05)
                }

                Stepper(value: $generationSettings.maxTokens, in: 32...4096, step: 32) {
                    HStack { Text("Max output"); Spacer(); Text("\(generationSettings.maxTokens) tokens").foregroundColor(.secondary) }
                }

                Toggle("Large Model Survival Mode", isOn: $generationSettings.largeModelSurvivalMode)
            }

            DisclosureGroup("Prompt and stop guards") {
                Picker("Prompt", selection: $generationSettings.promptStyle) {
                    Text("Universal").tag(PromptStyle.auto)
                    Text("Raw Debug").tag(PromptStyle.raw)
                }
                Picker("Model Behavior", selection: $generationSettings.textModelBehavior) {
                    ForEach(TextModelBehavior.allCases) { behavior in Text(behavior.title).tag(behavior) }
                }
                TextEditor(text: $generationSettings.stopSequencesText)
                    .frame(minHeight: 76)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                Text("Built-in stops always include LocalLLM start/stop markers and common role labels.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            DisclosureGroup("Live display and voice") {
                Picker("Display", selection: $generationSettings.liveDisplayMode) {
                    ForEach(LiveDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                if generationSettings.liveDisplayMode == .smoothLive {
                    Stepper(value: $generationSettings.typingCharactersPerSecond, in: 30...180, step: 10) {
                        HStack { Text("Typing speed"); Spacer(); Text("\(generationSettings.typingCharactersPerSecond)c/s").foregroundColor(.secondary) }
                    }
                }
                Picker("Voice Input", selection: $generationSettings.voiceInputMode) {
                    ForEach(VoiceInputMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Picker("Voice Output", selection: $generationSettings.voiceOutputMode) {
                    ForEach(VoiceOutputMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section(header: Text("Diagnostics"), footer: Text("Prompt Preview shows the exact universal prompt sent to the text backend.")) {
            Toggle("Detailed Errors", isOn: $generationSettings.detailedErrors)
            Button { showingPromptPreview = true } label: { Label("Prompt Preview", systemImage: "doc.text.magnifyingglass") }
        }
    }

    private var onboardingSection: some View {
        Section(header: Text("Onboarding & Help")) {
            Button {
                hasCompletedOnboarding = false
                presentationMode.wrappedValue.dismiss()
            } label: { Label("Run Onboarding Again", systemImage: "play.circle") }
            Label("Model folder: Files → On My iPhone → LocalLLM → Models", systemImage: "folder")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var aboutSection: some View {
        Section(header: Text("About")) {
            Label("Runs text chat on-device", systemImage: "lock.shield")
            Label("Local GGUF files stay supported", systemImage: "externaldrive")
            HStack { Text("Version"); Spacer(); Text(appVersionText).foregroundColor(.secondary) }
        }
    }

    @ViewBuilder
    private var statusSections: some View {
        if isImporting { Section { HStack { ProgressView(); Text("Copying model into LocalLLM/Models… Keep the app open.").foregroundColor(.secondary) } } }
        if let importStatus { Section { Text(importStatus).foregroundColor(.secondary) } }
        if let errorText { Section { Text(errorText).foregroundColor(.red) } }
    }

    private func modelRow(_ model: ModelReferenceEntity) -> some View {
        let info = ModelCapabilityInfo.resolve(for: model)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.displayName ?? "Model").lineLimit(1)
                Spacer()
                if isDefaultModel(model) { Text(defaultBadgeText(for: model)).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.accentColor.opacity(0.16))) }
            }
            Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)).font(.caption).foregroundColor(.secondary)
            Text("\(info.capability.title) • \(info.compatibility.title)").font(.caption2).foregroundColor(.secondary)
            if let path = model.originalPath { Text(path).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
        }.padding(.vertical, 4)
    }

    private func modelsMatching(_ capability: ModelCapability) -> [ModelReferenceEntity] {
        Array(models).filter { ModelPurposeStore.purpose(for: $0) == capability }
    }

    private var defaultModel: ModelReferenceEntity? {
        guard !generationSettings.defaultModelID.isEmpty else { return modelsMatching(.text).first }
        return modelsMatching(.text).first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) ?? modelsMatching(.text).first
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.26"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "27"
        return "\(version) (\(build))"
    }

    private func isDefaultModel(_ model: ModelReferenceEntity) -> Bool {
        let id = model.id?.uuidString ?? ""
        return generationSettings.defaultModelID == id || generationSettings.defaultImageModelID == id || generationSettings.defaultSpeechToTextModelID == id || generationSettings.defaultVoiceOutputModelID == id
    }

    private func defaultBadgeText(for model: ModelReferenceEntity) -> String {
        let id = model.id?.uuidString ?? ""
        if generationSettings.defaultModelID == id { return "Chat" }
        if generationSettings.defaultImageModelID == id { return "Image" }
        if generationSettings.defaultSpeechToTextModelID == id { return "Speech" }
        if generationSettings.defaultVoiceOutputModelID == id { return "Voice" }
        return "Default"
    }

    private func ensureVisibleModelsFolderExists() {
        do { _ = try ModelFileAccess.visibleModelsDirectory() } catch { errorText = error.localizedDescription }
    }

    private func scanVisibleModelsFolder() {
        do {
            let urls = try ModelFileAccess.visibleModelFileURLs()
            guard !urls.isEmpty else { importStatus = "No .gguf files found in LocalLLM/Models."; errorText = nil; return }
            var count = 0
            for url in urls {
                let bookmark = try ModelFileAccess.makeBookmarkForVisibleModel(at: url)
                let model = try PersistenceController.shared.upsertModel(from: bookmark, displayName: ModelFileAccess.displayName(for: url), originalPath: url.path, fileSize: ModelFileAccess.fileSize(at: url))
                let purpose = ModelCapabilityInfo.inferredPurpose(name: model.displayName)
                ModelPurposeStore.setPurpose(purpose, for: model)
                setDefaultIfNeeded(model, purpose: purpose)
                count += 1
            }
            importStatus = count == 1 ? "Added 1 model from Models folder." : "Added \(count) models from Models folder."
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func importModels(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImporting = true; importStatus = nil; errorText = nil
            Task {
                do {
                    var importedItems: [(bookmark: Data, displayName: String, originalPath: String, fileSize: Int64)] = []
                    for sourceURL in urls {
                        let copied = try ModelImportService.copyIntoModelsFolder(from: sourceURL)
                        let bookmark = try ModelFileAccess.makeBookmarkForVisibleModel(at: copied)
                        importedItems.append((bookmark, ModelFileAccess.displayName(for: copied), copied.path, ModelFileAccess.fileSize(at: copied)))
                    }
                    await MainActor.run {
                        do {
                            var count = 0
                            for item in importedItems {
                                let model = try PersistenceController.shared.upsertModel(from: item.bookmark, displayName: item.displayName, originalPath: item.originalPath, fileSize: item.fileSize)
                                let purpose = ModelCapabilityInfo.inferredPurpose(name: model.displayName)
                                ModelPurposeStore.setPurpose(purpose, for: model)
                                setDefaultIfNeeded(model, purpose: purpose)
                                count += 1
                            }
                            importStatus = count == 1 ? "Copied and imported 1 model." : "Copied and imported \(count) models."
                            errorText = nil
                        } catch { errorText = error.localizedDescription }
                        isImporting = false
                    }
                } catch { await MainActor.run { errorText = error.localizedDescription; isImporting = false } }
            }
        } catch { errorText = error.localizedDescription }
    }

    private func setDefaultIfNeeded(_ model: ModelReferenceEntity, purpose: ModelCapability) {
        guard let id = model.id?.uuidString else { return }
        switch purpose {
        case .text: if generationSettings.defaultModelID.isEmpty { generationSettings.defaultModelID = id }
        case .imageGeneration: if generationSettings.defaultImageModelID.isEmpty { generationSettings.defaultImageModelID = id }
        case .speechToText: if generationSettings.defaultSpeechToTextModelID.isEmpty { generationSettings.defaultSpeechToTextModelID = id }
        case .textToSpeech: if generationSettings.defaultVoiceOutputModelID.isEmpty { generationSettings.defaultVoiceOutputModelID = id }
        default: break
        }
    }
}
