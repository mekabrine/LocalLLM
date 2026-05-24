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
    @State private var isImporting = false
    @State private var errorText: String?

    private let onPick: (ModelReferenceEntity?) -> Void

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
                        .disabled(isImporting)
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import GGUF Model", systemImage: "doc")
                    }
                    .disabled(isImporting)
                }

                if isImporting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Importing model. Keep the app open.")
                                .foregroundColor(.secondary)
                        }
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
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use") {
                        onPick(selected)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(selected == nil || isImporting)
                }
            }
            .sheet(isPresented: $showingImporter) {
                ModelDocumentPicker(allowsMultipleSelection: true) { result in
                    showingImporter = false
                    handleImport(result)
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            isImporting = true
            errorText = nil

            Task {
                do {
                    var imported: [(Data, String, String, Int64)] = []
                    for url in urls {
                        let displayName = ModelFileAccess.displayName(for: url)
                        let originalPath = url.path
                        let fileSize = ModelFileAccess.fileSize(at: url)
                        let bookmark = try await ModelFileAccess.makeBookmarkAsync(for: url)
                        imported.append((bookmark, displayName, originalPath, fileSize))
                    }

                    await MainActor.run {
                        var firstImported: ModelReferenceEntity?
                        do {
                            for item in imported {
                                let model = try PersistenceController.shared.upsertModel(
                                    from: item.0,
                                    displayName: item.1,
                                    originalPath: item.2,
                                    fileSize: item.3
                                )
                                firstImported = firstImported ?? model
                            }

                            selected = firstImported ?? selected
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
