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
                assistantBehaviorSection
                generationModeSection
                manualGenerationSection
                liveDisplaySection
                modelDefaultsSection
                fileSection
                imageGenerationSection
                voiceSection
                diagnosticsSection
                importSection
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
                Text("Private local AI studio for chat, files, model routing, diagnostics, and local GGUF models.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var assistantBehaviorSection: some View {
        Section(header: Text("Assistant Behavior"), footer: Text("Small Model Protection uses a tiny assistant wrapper so small/base models reply instead of continuing your message.")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default System Message")
                TextEditor(text: $generationSettings.globalSystemMessage)
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }

            Picker("Prompt Style", selection: $generationSettings.promptStyle) {
                ForEach(PromptStyle.allCases) { style in Text(style.title).tag(style) }
            }

            Picker("Text Model Behavior", selection: $generationSettings.textModelBehavior) {
                ForEach(TextModelBehavior.allCases) { behavior in Text(behavior.title).tag(behavior) }
            }

            Toggle("Small Model Protection", isOn: $generationSettings.smallModelProtection)

            Picker("Reasoning", selection: $generationSettings.reasoningMode) {
                ForEach(ReasoningMode.allCases) { mode in Text(mode.title).tag(mode) }
            }

            Picker("Show Reasoning", selection: $generationSettings.reasoningDisplay) {
                ForEach(ReasoningDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
            }

            Button("Reset Assistant Behavior") {
                generationSettings.globalSystemMessage = GenerationSettings.defaultSystemMessage
                generationSettings.promptStyle = .auto
                generationSettings.textModelBehavior = .auto
                generationSettings.reasoningMode = .auto
                generationSettings.reasoningDisplay = .hidden
                generationSettings.smallModelProtection = true
            }
        }
    }

    private var generationModeSection: some View {
        Section(header: Text("Generation Mode"), footer: Text(currentAutoProfileDescription)) {
            Picker("Mode", selection: $generationSettings.generationMode) {
                ForEach(GenerationMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)

            Toggle("Large Model Survival Mode", isOn: $generationSettings.largeModelSurvivalMode)

            if let defaultModel {
                let profile = GenerationProfile.profile(forFileSize: defaultModel.fileSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.title).font(.headline)
                    Text(profile.subtitle).font(.caption).foregroundColor(.secondary)
                    Text("Auto uses \(profile.maxTokens) max tokens, \(profile.historyLimit) recent messages, and a \(profile.promptCharacterLimit) character prompt limit.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var manualGenerationSection: some View {
        if generationSettings.generationMode == .manual {
            Section(header: Text("Manual Generation")) {
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
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(generationSettings.temperature, format: .number.precision(.fractionLength(2))).foregroundColor(.secondary)
                    }
                    Slider(value: $generationSettings.temperature, in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Top P")
                        Spacer()
                        Text(generationSettings.topP, format: .number.precision(.fractionLength(2))).foregroundColor(.secondary)
                    }
                    Slider(value: $generationSettings.topP, in: 0.05...1, step: 0.05)
                }

                Stepper(value: $generationSettings.maxTokens, in: 32...4096, step: 32) {
                    HStack {
                        Text("Max output")
                        Spacer()
                        Text("\(generationSettings.maxTokens) tokens").foregroundColor(.secondary)
                    }
                }
            }
        }

        Section(header: Text("Output Guardrails")) {
            DisclosureGroup("Advanced stop sequences") {
                TextEditor(text: $generationSettings.stopSequencesText)
                    .frame(minHeight: 76)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                Text("One per line. Built-in filtering also cuts common fake role labels.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("Reset Generation Defaults") { generationSettings.resetSamplingDefaults() }
        }
    }

    private var liveDisplaySection: some View {
        Section(header: Text("Live Display")) {
            Picker("Display", selection: $generationSettings.liveDisplayMode) {
                ForEach(LiveDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
            }

            if generationSettings.liveDisplayMode == .smoothLive {
                Stepper(value: $generationSettings.typingCharactersPerSecond, in: 30...180, step: 10) {
                    HStack {
                        Text("Typing speed")
                        Spacer()
                        Text("\(generationSettings.typingCharactersPerSecond)c/s").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var modelDefaultsSection: some View {
        Section(header: Text("Default Models"), footer: Text("Model Library lets you choose each model's purpose. Defaults only show matching purposes.")) {
            Picker("Chat Model", selection: $generationSettings.defaultModelID) {
                Text("None").tag("")
                ForEach(modelsMatching(.text)) { model in Text(model.displayName ?? "Model").tag(model.id?.uuidString ?? "") }
            }
            Picker("Image Model", selection: $generationSettings.defaultImageModelID) {
                Text("None").tag("")
                ForEach(modelsMatching(.imageGeneration)) { model in Text(model.displayName ?? "Image Model").tag(model.id?.uuidString ?? "") }
            }
            Picker("Speech-to-Text", selection: $generationSettings.defaultSpeechToTextModelID) {
                Text("System Speech").tag("")
                ForEach(modelsMatching(.speechToText)) { model in Text(model.displayName ?? "Speech Model").tag(model.id?.uuidString ?? "") }
            }
            Picker("Voice Output", selection: $generationSettings.defaultVoiceOutputModelID) {
                Text("System Voice").tag("")
                ForEach(modelsMatching(.textToSpeech)) { model in Text(model.displayName ?? "Voice Model").tag(model.id?.uuidString ?? "") }
            }
            Button { showingModelLibrary = true } label: { Label("Open Model Library", systemImage: "library.fill") }
        }
    }

    private var fileSection: some View {
        Section(header: Text("Files"), footer: Text("Text, code, CSV, JSON, Markdown, and PDFs can be attached. Image uploads stay disabled until vision support is added.")) {
            Picker("File Handling", selection: $generationSettings.fileHandlingMode) {
                ForEach(FileHandlingMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Label("Supported: TXT, MD, JSON, CSV, PDF, Swift, Python, JS, HTML, CSS, logs", systemImage: "doc.text")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var imageGenerationSection: some View {
        Section(header: Text("Image Generation"), footer: Text("The toggle and model routing are ready. A dedicated local image backend is still required before images render.")) {
            Toggle("Enable by Default", isOn: $generationSettings.imageGenerationEnabledByDefault)
            Picker("Image Size", selection: $generationSettings.imageSize) {
                ForEach(ImageGenerationSize.allCases) { size in Text(size.title).tag(size) }
            }
            Picker("Quality", selection: $generationSettings.imageQuality) {
                ForEach(ImageGenerationQuality.allCases) { quality in Text(quality.title).tag(quality) }
            }
        }
    }

    private var voiceSection: some View {
        Section(header: Text("Voice"), footer: Text("Voice controls are prepared for system/local speech input and output. Local model inference needs dedicated STT/TTS backends.")) {
            Picker("Voice Input", selection: $generationSettings.voiceInputMode) {
                ForEach(VoiceInputMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Picker("Voice Output", selection: $generationSettings.voiceOutputMode) {
                ForEach(VoiceOutputMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section(header: Text("Diagnostics"), footer: Text("Prompt Preview shows the full prompt for every style using the same builder as chat generation.")) {
            Toggle("Detailed Errors", isOn: $generationSettings.detailedErrors)
            Toggle("Show Prompt Preview", isOn: $generationSettings.showPromptPreview)
            Button { showingPromptPreview = true } label: { Label("Prompt Preview", systemImage: "doc.text.magnifyingglass") }
        }
    }

    private var importSection: some View {
        Section(header: Text("Import"), footer: Text("Use Model Library tabs when you want to choose a model's purpose during import.")) {
            if models.isEmpty {
                Text("No imported models yet.").foregroundColor(.secondary)
            } else {
                ForEach(models) { model in modelRow(model) }
            }
            Button { scanVisibleModelsFolder() } label: { Label("Scan Models Folder", systemImage: "folder.badge.gearshape") }.disabled(isImporting)
            Button { showingImporter = true } label: { Label("Import Models", systemImage: "square.and.arrow.down") }.disabled(isImporting)
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
            Label("Image, voice, and vision require dedicated backends", systemImage: "sparkles")
            HStack { Text("Version"); Spacer(); Text(appVersionText).foregroundColor(.secondary) }
        }
    }

    @ViewBuilder
    private var statusSections: some View {
        if isImporting { Section { HStack { ProgressView(); Text("Importing model… Keep the app open.").foregroundColor(.secondary) } } }
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

    private var currentAutoProfileDescription: String {
        guard generationSettings.generationMode == .auto else { return "Manual mode uses your custom settings below." }
        return defaultModel == nil ? "Auto mode will choose safe defaults after a model is selected." : "Auto mode adjusts prompt style, model behavior, context length, and output length based on the selected model size."
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.13"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "14"
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
                    for url in urls {
                        let bookmark = try await ModelFileAccess.makeBookmarkAsync(for: url)
                        importedItems.append((bookmark, ModelFileAccess.displayName(for: url), url.path, ModelFileAccess.fileSize(at: url)))
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
                            importStatus = count == 1 ? "Imported 1 model." : "Imported \(count) models."
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
