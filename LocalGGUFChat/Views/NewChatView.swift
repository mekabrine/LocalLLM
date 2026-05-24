import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct NewChatView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var title: String = ""
    @State private var selectedModel: ModelReferenceEntity?
    @State private var showingImporter = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Chat")) {
                    TextField("Title (optional)", text: $title)
                }

                Section(header: Text("Model")) {
                    if models.isEmpty {
                        Text("No models yet. Import .gguf files to add them.").foregroundColor(.secondary)
                    } else {
                        ForEach(models) { m in
                            Button {
                                selectedModel = m
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.displayName ?? "Model")
                                        if let path = m.originalPath {
                                            Text(path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selectedModel == m {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import .gguf Files", systemImage: "doc")
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { createChat() }
                        .disabled(selectedModel == nil)
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

    private func selectInitialModel() {
        guard selectedModel == nil else { return }

        if !generationSettings.defaultModelID.isEmpty,
           let defaultModel = models.first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) {
            selectedModel = defaultModel
            return
        }

        selectedModel = models.first
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            var firstImported: ModelReferenceEntity?
            for url in urls {
                let model = try PersistenceController.shared.upsertModel(
                    from: try ModelFileAccess.makeBookmark(for: url),
                    displayName: ModelFileAccess.displayName(for: url),
                    originalPath: url.path,
                    fileSize: ModelFileAccess.fileSize(at: url)
                )

                firstImported = firstImported ?? model

                if generationSettings.defaultModelID.isEmpty, let id = model.id {
                    generationSettings.defaultModelID = id.uuidString
                }
            }

            selectedModel = firstImported ?? selectedModel
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func createChat() {
        guard let selectedModel else { return }
        _ = PersistenceController.shared.createChat(title: title, model: selectedModel)
        presentationMode.wrappedValue.dismiss()
    }
}
