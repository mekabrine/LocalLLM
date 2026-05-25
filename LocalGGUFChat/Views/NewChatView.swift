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
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Chat")) {
                    TextField("Title (optional)", text: $title)
                }

                Section(header: Text("Model"), footer: Text("Imported files are copied into LocalLLM/Models so iOS file permissions do not expire.")) {
                    if textModels.isEmpty {
                        Text("No text chat models yet. Import a .gguf file to add one.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(textModels) { m in
                            Button { selectedModel = m } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.displayName ?? "Model")
                                        Text(modelSubtitle(for: m))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedModel == m { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                                }
                            }
                            .disabled(isImporting)
                        }
                    }

                    Button { showingImporter = true } label: {
                        Label("Import Text Model", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting)
                }

                Section(header: Text("AI")) {
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

                if isImporting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Copying model into LocalLLM/Models… Keep the app open.")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(.red) }
                }
            }
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

    private var textModels: [ModelReferenceEntity] {
        Array(models).filter { model in ModelPurposeStore.purpose(for: model) == .text }
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

    private func modelSubtitle(for model: ModelReferenceEntity) -> String {
        let size = ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)
        let info = ModelCapabilityInfo.resolve(for: model)
        let runtime = ModelRuntimeSupport.resolve(purpose: info.capability, fileName: model.displayName ?? "", fileSize: model.fileSize)
        return "\(size) • \(runtime.title) • \(info.profile.title)"
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
