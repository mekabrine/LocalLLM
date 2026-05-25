import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct NewChatView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

    var onCreate: (ChatEntity) -> Void = { _ in }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var title: String = ""
    @State private var selectedModel: ModelReferenceEntity?
    @State private var searchText = ""
    @State private var modelFilter: NewChatModelFilter = .all
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    chatCard
                    modelSelector
                    aiSettingsCard
                    importStatus
                    errorCard
                }
                .padding(18)
            }
            .background(StudioTheme.background.ignoresSafeArea())
            .navigationTitle("New Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }.disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { createChat() }.disabled(selectedModel == nil || isImporting)
                }
            }
            .onAppear(perform: selectInitialModel)
            .sheet(isPresented: $showingImporter) {
                ModelDocumentPicker(allowsMultipleSelection: true) { result in
                    showingImporter = false
                    handleImport(result)
                }
            }
        }
    }

    private var chatCard: some View {
        StudioGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                TextField("Title (optional)", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var modelSelector: some View {
        StudioGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Choose a Model", systemImage: "cpu.fill")
                        .font(.headline)
                    Spacer()
                    Button { showingImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting)
                }

                Text("Tap a card to select it. Long-press a card for a quick select action. Imported files are copied into LocalLLM/Models.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Search models", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                Picker("Filter", selection: $modelFilter) {
                    ForEach(NewChatModelFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if filteredModels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(textModels.isEmpty ? "No text models yet" : "No matching models")
                            .font(.headline)
                        Text(textModels.isEmpty ? "Import or download a GGUF text model first." : "Clear the search or choose a different filter.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredModels) { model in
                            NewChatModelCard(
                                model: model,
                                isSelected: selectedModel == model,
                                isDefault: model.id?.uuidString == generationSettings.defaultModelID,
                                onSelect: { select(model) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var aiSettingsCard: some View {
        StudioGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Picker("Response Length", selection: $generationSettings.responseLength) {
                    ForEach(SimpleResponseLength.allCases) { length in Text(length.title).tag(length) }
                }
                Picker("Memory", selection: $generationSettings.conversationMemory) {
                    ForEach(ConversationMemoryMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Picker("Speed", selection: $generationSettings.speedMode) {
                    ForEach(AISpeedMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            }
        }
    }

    @ViewBuilder
    private var importStatus: some View {
        if isImporting {
            StudioGlassCard(cornerRadius: 18) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Copying model into LocalLLM/Models… Keep the app open.")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let errorText {
            StudioGlassCard(cornerRadius: 18, borderColor: StudioTheme.danger.opacity(0.35)) {
                Text(errorText).foregroundColor(StudioTheme.danger)
            }
        }
    }

    private var textModels: [ModelReferenceEntity] {
        Array(models).filter { model in ModelPurposeStore.purpose(for: model) == .text }
    }

    private var filteredModels: [ModelReferenceEntity] {
        textModels.filter { model in
            let name = model.displayName ?? ""
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !name.localizedCaseInsensitiveContains(searchText) { return false }
            let info = ModelCapabilityInfo.resolve(for: model)
            let runtime = ModelRuntimeSupport.resolve(purpose: info.capability, fileName: name, fileSize: model.fileSize)
            switch modelFilter {
            case .all: return true
            case .runsNow: return runtime == .runsNow
            case .small: return model.fileSize < 2_000_000_000
            case .large: return model.fileSize >= 4_000_000_000
            }
        }
    }

    private func selectInitialModel() {
        guard selectedModel == nil else { return }
        if !generationSettings.defaultModelID.isEmpty,
           let defaultModel = textModels.first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) {
            selectedModel = defaultModel
            return
        }
        selectedModel = textModels.first
    }

    private func select(_ model: ModelReferenceEntity) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedModel = model
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImporting = true
            errorText = nil

            Task {
                do {
                    var imported: [(bookmark: Data, displayName: String, originalPath: String, fileSize: Int64)] = []
                    for sourceURL in urls {
                        let copiedURL = try ModelImportService.copyIntoModelsFolder(from: sourceURL)
                        let bookmark = try ModelFileAccess.makeBookmarkForVisibleModel(at: copiedURL)
                        imported.append((bookmark, ModelFileAccess.displayName(for: copiedURL), copiedURL.path, ModelFileAccess.fileSize(at: copiedURL)))
                    }

                    await MainActor.run {
                        var firstImported: ModelReferenceEntity?
                        do {
                            for item in imported {
                                let model = try PersistenceController.shared.upsertModel(
                                    from: item.bookmark,
                                    displayName: item.displayName,
                                    originalPath: item.originalPath,
                                    fileSize: item.fileSize
                                )
                                ModelPurposeStore.setPurpose(.text, for: model)
                                firstImported = firstImported ?? model
                                if generationSettings.defaultModelID.isEmpty, let id = model.id { generationSettings.defaultModelID = id.uuidString }
                            }
                            selectedModel = firstImported ?? selectedModel
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

    private func createChat() {
        guard let selectedModel else { return }
        let chat = PersistenceController.shared.createChat(title: title, model: selectedModel)
        presentationMode.wrappedValue.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCreate(chat) }
    }
}

private enum NewChatModelFilter: String, CaseIterable, Identifiable {
    case all
    case runsNow
    case small
    case large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .runsNow: return "Runs"
        case .small: return "Small"
        case .large: return "Large"
        }
    }
}

private struct NewChatModelCard: View {
    @ObservedObject var model: ModelReferenceEntity
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void

    private var info: ModelCapabilityInfo { ModelCapabilityInfo.resolve(for: model) }
    private var runtime: ModelRuntimeSupport {
        ModelRuntimeSupport.resolve(purpose: info.capability, fileName: model.displayName ?? "", fileSize: model.fileSize)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    StudioIconCircle(systemName: info.capability.systemImage, color: .accentColor, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.displayName ?? "Model")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundColor(.accentColor) }
                }

                HStack(spacing: 6) {
                    badge(runtime.title, color: runtimeColor)
                    badge(info.compatibility.title, color: compatibilityColor)
                    if isDefault { badge("Default", color: StudioTheme.success) }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(StudioTheme.surface.opacity(isSelected ? 0.95 : 0.65)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isSelected ? Color.accentColor : StudioTheme.border, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .contextMenu { Button(action: onSelect) { Label("Select Model", systemImage: "checkmark.circle") } }
        .onTapGesture(count: 2, perform: onSelect)
        .onLongPressGesture(perform: onSelect)
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)
        return "\(size) • \(info.architecture) • \(info.quantization) • \(info.profile.title)"
    }

    private var runtimeColor: Color {
        switch runtime {
        case .runsNow: return StudioTheme.success
        case .tooLarge, .unsupportedFormat: return StudioTheme.danger
        case .needsImageBackend, .needsSpeechBackend, .needsVoiceBackend, .needsVisionBackend: return StudioTheme.warning
        case .unknown: return StudioTheme.secondaryText
        }
    }

    private var compatibilityColor: Color {
        switch info.compatibility {
        case .supported, .likelySupported: return StudioTheme.success
        case .risky, .veryHighRisk: return StudioTheme.warning
        case .tooLarge, .unsupportedArchitecture: return StudioTheme.danger
        case .unknown: return StudioTheme.secondaryText
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
