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
    @State private var isImporting = false
    @State private var importStatus: String?
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                introSection
                assistantBehaviorSection
                generationModeSection
                generationControlsSection
                liveDisplaySection
                modelDefaultsSection
                fileSection
                imageGenerationSection
                voiceSection
                diagnosticsSection
                modelsSection
                onboardingSection
                aboutSection
                importStateSections
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
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("LocalLLM", systemImage: "sparkles")
                    .font(.title2.weight(.bold))
                Text("Private local AI studio for chat, files, voice routing, image-generation routing, diagnostics, and local GGUF models.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var assistantBehaviorSection: some View {
        Section(header: Text("Assistant Behavior"), footer: Text("Small Model Protection uses plain prompts and disables reasoning for tiny models to reduce prompt continuation.")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default System Message")
                TextEditor(text: $generationSettings.globalSystemMessage)
                    .frame(minHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }

            Picker("Prompt Style", selection: $generationSettings.promptStyle) {
                ForEach(PromptStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            Toggle("Small Model Protection", isOn: $generationSettings.smallModelProtection)

            Picker("Reasoning", selection: $generationSettings.reasoningMode) {
                ForEach(ReasoningMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Show Reasoning", selection: $generationSettings.reasoningDisplay) {
                ForEach(ReasoningDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Button("Reset Assistant Behavior") {
                generationSettings.globalSystemMessage = GenerationSettings.defaultSystemMessage
                generationSettings.promptStyle = .auto
                generationSettings.reasoningMode = .auto
                generationSettings.reasoningDisplay = .hidden
                generationSettings.smallModelProtection = true
            }
        }
    }

    private var generationModeSection: some View {
        Section(header: Text("Generation Mode"), footer: Text(currentAutoProfileDescription)) {
            Picker("Mode", selection: $generationSettings.generationMode) {
                ForEach(GenerationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Large Model Survival Mode", isOn: $generationSettings.largeModelSurvivalMode)

            if let defaultModel {
                let profile = GenerationProfile.profile(forFileSize: defaultModel.fileSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.title)
                        .font(.headline)
                    Text(profile.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Auto uses \(profile.maxTokens) max tokens, \(profile.historyLimit) recent messages, and a \(profile.promptCharacterLimit) character prompt limit.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var generationControlsSection: some View {
        if generationSettings.generationMode == .manual {
            Section(header: Text("Manual Generation"), footer: Text("Temperature controls creativity. Higher values are more varied; lower values are more predictable.")) {
                ForEach(GenerationPreset.all) { preset in
                    Button { generationSettings.applyPreset(preset) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.title)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(preset.maxTokens)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(isImporting)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(generationSettings.temperature, format: .number.precision(.fractionLength(2)))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $generationSettings.temperature, in: 0.0...2.0, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top P")
                        Spacer()
                        Text(generationSettings.topP, format: .number.precision(.fractionLength(2)))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $generationSettings.topP, in: 0.05...1.0, step: 0.05)
                }

                Stepper(value: $generationSettings.maxTokens, in: 32...4096, step: 32) {
                    HStack {
                        Text("Max output")
                        Spacer()
                        Text("\(generationSettings.maxTokens) tokens")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        Section(header: Text("Output Guardrails")) {
            DisclosureGroup("Advanced stop sequences") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $generationSettings.stopSequencesText)
                        .frame(minHeight: 76)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    Text("One per line. Built-in filtering also cuts common fake role labels.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button("Reset Generation Defaults") { generationSettings.resetSamplingDefaults() }
                .disabled(isImporting)
        }
    }

    private var liveDisplaySection: some View {
        Section(header: Text("Live Display"), footer: Text("Smooth Live streams from the model but reveals chunks with a clean typing animation.")) {
            Picker("Display", selection: $generationSettings.liveDisplayMode) {
                ForEach(LiveDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            if generationSettings.liveDisplayMode == .smoothLive {
                Stepper(value: $generationSettings.typingCharactersPerSecond, in: 30...180, step: 10) {
                    HStack {
                        Text("Typing speed")
                        Spacer()
                        Text("\(generationSettings.typingCharactersPerSecond)c/s")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var modelDefaultsSection: some View {
        Section(header: Text("Default Models"), footer: Text("Each feature uses its own model slot. Text GGUF models are not automatically image or voice models.")) {
            Picker("Chat Model", selection: $generationSettings.defaultModelID) {
                Text("None").tag("")
                ForEach(modelsMatching(.text)) { model in
                    Text(model.displayName ?? "Model").tag(model.id?.uuidString ?? "")
                }
            }

            Picker("Image Model", selection: $generationSettings.defaultImageModelID) {
                Text("None").tag("")
                ForEach(modelsMatching(.imageGeneration)) { model in
                    Text(model.displayName ?? "Image Model").tag(model.id?.uuidString ?? "")
                }
            }

            Picker("Speech-to-Text", selection: $generationSettings.defaultSpeechToTextModelID) {
                Text("System Speech").tag("")
                ForEach(modelsMatching(.speechToText)) { model in
                    Text(model.displayName ?? "Speech Model").tag(model.id?.uuidString ?? "")
                }
            }

            Picker("Voice Output", selection: $generationSettings.defaultVoiceOutputModelID) {
                Text("System Voice").tag("")
                ForEach(modelsMatching(.textToSpeech)) { model in
                    Text(model.displayName ?? "Voice Model").tag(model.id?.uuidString ?? "")
                }
            }

            Button { showingModelLibrary = true } label: {
                Label("Open Model Library", systemImage: "library.fill")
            }
        }
    }

    private var fileSection: some View {
        Section(header: Text("Files"), footer: Text("Text, code, CSV, JSON, Markdown, and PDFs can be attached. Image uploads stay disabled until vision support is added.")) {
            Picker("File Handling", selection: $generationSettings.fileHandlingMode) {
                ForEach(FileHandlingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Label("Supported: TXT, MD, JSON, CSV, PDF, Swift, Python, JS, HTML, CSS, logs", systemImage: "doc.text")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var imageGenerationSection: some View {
        Section(header: Text("Image Generation"), footer: Text("The composer toggle and model routing are ready. A dedicated local image backend still needs to be connected before images can render.")) {
            Toggle("Enable by Default", isOn: $generationSettings.imageGenerationEnabledByDefault)

            Picker("Image Size", selection: $generationSettings.imageSize) {
                ForEach(ImageGenerationSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }

            Picker("Quality", selection: $generationSettings.imageQuality) {
                ForEach(ImageGenerationQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
        }
    }

    private var voiceSection: some View {
        Section(header: Text("Voice"), footer: Text("Voice controls are prepared for local/system speech input and output. Local model inference requires dedicated STT/TTS backends.")) {
            Picker("Voice Input", selection: $generationSettings.voiceInputMode) {
                ForEach(VoiceInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Voice Output", selection: $generationSettings.voiceOutputMode) {
                ForEach(VoiceOutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section(header: Text("Diagnostics"), footer: Text("Detailed errors show the stage, model size, compatibility, raw backend error, and suggested fixes.")) {
            Toggle("Detailed Errors", isOn: $generationSettings.detailedErrors)
            Toggle("Show Prompt Preview", isOn: $generationSettings.showPromptPreview)
        }
    }

    private var modelsSection: some View {
        Section(header: Text("Import"), footer: Text("Put large .gguf files in Files → On My iPhone → LocalLLM → Models, then tap Scan Models Folder. This avoids copying 1GB+ files through the picker.")) {
            if models.isEmpty {
                Text("No imported models yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(models) { model in
                    modelRow(model)
                }
            }

            Button { scanVisibleModelsFolder() } label: {
                Label("Scan Models Folder", systemImage: "folder.badge.gearshape")
            }
            .disabled(isImporting)

            Button { showingImporter = true } label: {
                Label("Import Models", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)
        }
    }

    private var onboardingSection: some View {
        Section(header: Text("Onboarding & Help")) {
            Button {
                hasCompletedOnboarding = false
                presentationMode.wrappedValue.dismiss()
            } label: {
                Label("Run Onboarding Again", systemImage: "play.circle")
            }

            Label("Model folder: Files → On My iPhone → LocalLLM → Models", systemImage: "folder")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var aboutSection: some View {
        Section(header: Text("About")) {
            Label("Runs text chat on-device", systemImage: "lock.shield")
            Label("Image, voice, and vision require dedicated backends", systemImage: "sparkles")
            HStack {
                Text("Version")
                Spacer()
                Text(appVersionText)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var importStateSections: some View {
        if isImporting {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Importing model… Keep the app open.")
                        .foregroundColor(.secondary)
                }
            }
        }

        if let importStatus {
            Section { Text(importStatus).foregroundColor(.secondary) }
        }

        if let errorText {
            Section { Text(errorText).foregroundColor(.red) }
        }
    }

    private func modelRow(_ model: ModelReferenceEntity) -> some View {
        let info = ModelCapabilityInfo.infer(name: model.displayName, fileSize: model.fileSize)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.displayName ?? "Model")
                    .lineLimit(1)
                Spacer()
                if isDefaultModel(model) {
                    Text(defaultBadgeText(for: model))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                }
            }
            Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text(info.capability.title)
                Text("•")
                Text(info.compatibility.title)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            if let path = model.originalPath {
                Text(path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func modelsMatching(_ capability: ModelCapability) -> [ModelReferenceEntity] {
        Array(models).filter { model in
            ModelCapabilityInfo.infer(name: model.displayName, fileSize: model.fileSize).capability == capability
        }
    }

    private var defaultModel: ModelReferenceEntity? {
        guard !generationSettings.defaultModelID.isEmpty else { return modelsMatching(.text).first }
        return models.first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) ?? modelsMatching(.text).first
    }

    private var currentAutoProfileDescription: String {
        guard generationSettings.generationMode == .auto else { return "Manual mode uses your custom settings below." }
        guard defaultModel != nil else { return "Auto mode will choose safe defaults after a model is selected." }
        return "Auto mode adjusts prompt style, context length, and output length based on the selected model size."
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.11"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "12"
        return "\(version) (\(build))"
    }

    private func isDefaultModel(_ model: ModelReferenceEntity) -> Bool {
        let id = model.id?.uuidString ?? ""
        return generationSettings.defaultModelID == id ||
        generationSettings.defaultImageModelID == id ||
        generationSettings.defaultSpeechToTextModelID == id ||
        generationSettings.defaultVoiceOutputModelID == id
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
        do { _ = try ModelFileAccess.visibleModelsDirectory() }
        catch { errorText = error.localizedDescription }
    }

    private func scanVisibleModelsFolder() {
        do {
            let urls = try ModelFileAccess.visibleModelFileURLs()
            guard !urls.isEmpty else {
                importStatus = "No .gguf files found in LocalLLM/Models."
                errorText = nil
                return
            }

            var count = 0
            for url in urls {
                let bookmark = try ModelFileAccess.makeBookmarkForVisibleModel(at: url)
                let model = try PersistenceController.shared.upsertModel(
                    from: bookmark,
                    displayName: ModelFileAccess.displayName(for: url),
                    originalPath: url.path,
                    fileSize: ModelFileAccess.fileSize(at: url)
                )
                setDefaultIfNeeded(model)
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

            isImporting = true
            importStatus = nil
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

                            importStatus = count == 1 ? "Imported 1 model." : "Imported \(count) models."
                            errorText = nil
                        } catch { errorText = error.localizedDescription }
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        errorText = error.localizedDescription
                        isImporting = false
                    }
                }
            }
        } catch { errorText = error.localizedDescription }
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
