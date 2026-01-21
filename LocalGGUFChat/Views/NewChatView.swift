
import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct NewChatView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.presentationMode) private var presentationMode

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var title: String = ""
    @State private var selectedModel: ModelReferenceEntity?
    @State private var showingImporter = false
    @State private var errorText: String?

    private var ggufType: UTType { UTType(filenameExtension: "gguf") ?? .data }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Chat")) {
                    TextField("Title (optional)", text: $title)
                }

                Section(header: Text("Model")) {
                    if models.isEmpty {
                        Text("No models yet. Pick a .gguf file to add one.").foregroundColor(.secondary)
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
                        Label("Pick .gguf from Files", systemImage: "doc")
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [ggufType],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let bookmark = try ModelFileAccess.makeBookmark(for: url)
            let name = ModelFileAccess.displayName(for: url)
            let size = ModelFileAccess.fileSize(at: url)

            let model = try PersistenceController.shared.upsertModel(
                from: bookmark,
                displayName: name,
                originalPath: url.path,
                fileSize: size
            )
            selectedModel = model
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
