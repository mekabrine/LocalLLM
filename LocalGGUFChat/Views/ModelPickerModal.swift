
import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct ModelPickerModal: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.presentationMode) private var presentationMode

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var selected: ModelReferenceEntity?
    @State private var showingImporter = false
    @State private var errorText: String?

    private let onPick: (ModelReferenceEntity?) -> Void
    private var ggufType: UTType { UTType(filenameExtension: "gguf") ?? .data }

    init(selected: ModelReferenceEntity?, onPick: @escaping (ModelReferenceEntity?) -> Void) {
        _selected = State(initialValue: selected)
        self.onPick = onPick
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Current")) {
                    if let selected {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selected.displayName ?? "Model").font(.headline)
                            if let p = selected.originalPath {
                                Text(p).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: selected.fileSize, countStyle: .file))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Text("No model selected").foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Models")) {
                    ForEach(models) { m in
                        Button {
                            selected = m
                        } label: {
                            HStack {
                                Text(m.displayName ?? "Model")
                                Spacer()
                                if selected == m { Image(systemName: "checkmark").foregroundColor(.accentColor) }
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
                    Section { Text(errorText).foregroundColor(.red) }
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use") {
                        onPick(selected)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(selected == nil)
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
            selected = model
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
