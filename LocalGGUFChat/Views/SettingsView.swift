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
    @State private var importStatus: String?
    @State private var errorText: String?

    private var ggufType: UTType { UTType(filenameExtension: "gguf") ?? .data }

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
                }

                Section(header: Text("Models"), footer: Text("Imported models are stored as security-scoped bookmarks, so the app can reopen them from Files later without copying large GGUF files into the app container.")) {
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
                        showingImporter = true
                    } label: {
                        Label("Import .gguf Models", systemImage: "square.and.arrow.down")
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
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [ggufType],
                allowsMultipleSelection: true
            ) { result in
                importModels(result)
            }
        }
    }

    private func importModels(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            var imported = 0
            for url in urls {
                let bookmark = try ModelFileAccess.makeBookmark(for: url)
                let model = try PersistenceController.shared.upsertModel(
                    from: bookmark,
                    displayName: ModelFileAccess.displayName(for: url),
                    originalPath: url.path,
                    fileSize: ModelFileAccess.fileSize(at: url)
                )

                if generationSettings.defaultModelID.isEmpty, let id = model.id {
                    generationSettings.defaultModelID = id.uuidString
                }

                imported += 1
            }

            importStatus = imported == 1 ? "Imported 1 model." : "Imported \(imported) models."
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
