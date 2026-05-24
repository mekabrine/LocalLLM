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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.displayName ?? "Model")
                                    Text(ByteCountFormatter.string(fromByteCount: m.fileSize, countStyle: .file))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selected == m { Image(systemName: "checkmark").foregroundColor(.accentColor) }
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
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        }
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
            }

            selected = firstImported ?? selected
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
