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
            .onAppear {
                ensureVisibleModelsFolderExists()
            }
            .sheet(isPresented: $showingImporter) {
                ModelDocumentPicker(allowsMultipleSelection: true) { result in
                    showingImporter = false
                    importModels(result)
                }
            }
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("LocalLLM", systemImage: "sparkles")
                    .font(.title2.weight(.bold))
                Text("Private local chats powered by GGUF models on this device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var assistantBehaviorSection: some View {
        Section(header: Text("Assistant Behavior"), footer: Text("The default system message applies to new and existing chats unless a chat adds its own instructions.")) {
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
                    Button {
                        generationSettings.applyPreset(preset)
                    } label: {
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

            Button("Reset Generation Defaults") {
                generationSettings.resetSamplingDefaults()
            }
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

    private var modelsSection: some View {
        Section(header: Text("Models"), footer: Text("Put large .gguf files in Files → On My iPhone → LocalGGUFChat → Models, then tap Scan Models Folder. This avoids copying 1GB+ files through the picker.")) {
            if models.isEmpty {
                Text("No imported models yet.")
                    .foregroundColor(.secondary)
            } else {
                Picker("Default model", selection: $generationSettings.defaultModelID) {
                    Text("None").tag("")
                    ForEach(models) { model in
                        Text(model.displayName ?? "Model")
                            .tag(model.id?.uuidString ?? "")
                    }
                }
                .disabled(isImporting)

                ForEach(models) { model in
                    modelRow(model)
                }
            }

            Button {
                scanVisibleModelsFolder()
            } label: {
                Label("Scan Models Folder", systemImage: "folder.badge.gearshape")
            }
            .disabled(isImporting)

            Button {
                showingImporter = true
            } label: {
                Label("Import GGUF Models", systemImage: "square.and.arrow.down")
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

            Label("Model folder: Files → On My iPhone → LocalGGUFChat → Models", systemImage: "folder")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var aboutSection: some View {
        Section(header: Text("About")) {
            Label("Runs fully on-device", systemImage: "lock.shield")
            Label("Supports local GGUF models", systemImage: "doc.fill")
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
            Section {
                Text(importStatus)
                    .foregroundColor(.secondary)
            }
        }

        if let errorText {
            Section {
                Text(errorText)
                    .foregroundColor(.red)
            }
        }
    }

    private func modelRow(_ model: ModelReferenceEntity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.displayName ?? "Model")
                if model.id?.uuidString == generationSettings.defaultModelID {
                    Text("Default")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                }
            }
            Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(GenerationProfile.profile(forFileSize: model.fileSize).title)
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

    private var defaultModel: ModelReferenceEntity? {
        guard !generationSettings.defaultModelID.isEmpty else { return models.first }
        return models.first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) ?? models.first
    }

    private var currentAutoProfileDescription: String {
        guard generationSettings.generationMode == .auto else {
            return "Manual mode uses your custom settings below."
        }
        guard defaultModel != nil else {
            return "Auto mode will choose safe defaults after a model is selected."
        }
        return "Auto mode adjusts prompt style, context length, and output length based on the selected model size."
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.9"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "10"
        return "\(version) (\(build))"
    }

    private func ensureVisibleModelsFolderExists() {
        do {
            _ = try ModelFileAccess.visibleModelsDirectory()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func scanVisibleModelsFolder() {
        do {
            let urls = try ModelFileAccess.visibleModelFileURLs()
            guard !urls.isEmpty else {
                importStatus = "No .gguf files found in LocalGGUFChat/Models."
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

                if generationSettings.defaultModelID.isEmpty, let id = model.id {
                    generationSettings.defaultModelID = id.uuidString
                }

                count += 1
            }

            importStatus = count == 1 ? "Added 1 model from Models folder." : "Added \(count) models from Models folder."
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
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

                                if generationSettings.defaultModelID.isEmpty, let id = model.id {
                                    generationSettings.defaultModelID = id.uuidString
                                }

                                count += 1
                            }

                            importStatus = count == 1 ? "Imported 1 model." : "Imported \(count) models."
                            errorText = nil
                        } catch {
                            errorText = error.localizedDescription
                        }
                        isImporting = false
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
        }
    }
}
