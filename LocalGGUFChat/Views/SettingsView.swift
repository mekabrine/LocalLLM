import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

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
                Section(header: Text("Generation"), footer: Text("Temperature controls creativity. Higher values are more varied; lower values are more predictable.")) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stop sequences")
                        TextEditor(text: $generationSettings.stopSequencesText)
                            .frame(minHeight: 76)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                        Text("One per line. The default prevents the model from continuing as the user.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Reset Generation Defaults") {
                        generationSettings.resetSamplingDefaults()
                    }
                    .disabled(isImporting)
                }

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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName ?? "Model")
                                Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let path = model.originalPath {
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
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
