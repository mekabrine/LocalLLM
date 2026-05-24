import SwiftUI
import CoreData

struct ModelFolderManagerView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    let defaultPurpose: ModelCapability

    @State private var files: [LocalModelFile] = []
    @State private var selectedPurpose: ModelCapability
    @State private var message: String?
    @State private var errorText: String?

    init(defaultPurpose: ModelCapability) {
        self.defaultPurpose = defaultPurpose
        _selectedPurpose = State(initialValue: defaultPurpose)
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Models Folder"), footer: Text("Files here are stored in Files → On My iPhone → LocalLLM → Models. Hugging Face downloads are saved here too.")) {
                    HStack {
                        Text("Import missing files as")
                        Spacer()
                        Picker("Purpose", selection: $selectedPurpose) {
                            ForEach(ModelCapability.allCases) { purpose in
                                Text(purpose.importTitle).tag(purpose)
                            }
                        }
                        .labelsHidden()
                    }

                    Button { scanFolder() } label: {
                        Label("Refresh File List", systemImage: "arrow.clockwise")
                    }

                    Button { importMissingFiles() } label: {
                        Label("Import Missing Files", systemImage: "tray.and.arrow.down")
                    }

                    if let message { Text(message).font(.caption).foregroundColor(.secondary) }
                    if let errorText { Text(errorText).font(.caption).foregroundColor(.red) }
                }

                Section(header: Text("Files")) {
                    if files.isEmpty {
                        Text("No files found in the Models folder.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(files) { file in
                            fileRow(file)
                        }
                    }
                }
            }
            .navigationTitle("Manage Models Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { scanFolder() }
        }
    }

    private func fileRow(_ file: LocalModelFile) -> some View {
        let matchingModel = models.first { $0.originalPath == file.url.path }
        let purpose = matchingModel.map { ModelPurposeStore.purpose(for: $0) }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(file.url.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    if matchingModel == nil {
                        Button("Import as \(selectedPurpose.importTitle)") { importFile(file, purpose: selectedPurpose) }
                    } else if let purpose {
                        Button("Imported as \(purpose.title)") { }
                            .disabled(true)
                    }
                    Button(role: .destructive) { deleteFile(file) } label: { Text("Delete File") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            HStack(spacing: 6) {
                badge(file.sizeText, color: .secondary)
                if let purpose {
                    badge("Imported: \(purpose.title)", color: .green)
                } else {
                    badge("Not in Library", color: .orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func scanFolder() {
        do {
            let folder = try ModelFileAccess.visibleModelsDirectory()
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            files = urls.compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { return nil }
                return LocalModelFile(url: url, size: Int64(values?.fileSize ?? 0))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            message = "Found \(files.count) file\(files.count == 1 ? "" : "s")."
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importMissingFiles() {
        let missing = files.filter { file in !models.contains(where: { $0.originalPath == file.url.path }) }
        guard !missing.isEmpty else {
            message = "All folder files are already in the library."
            return
        }
        var count = 0
        for file in missing {
            if importFile(file, purpose: selectedPurpose, silent: true) { count += 1 }
        }
        message = "Imported \(count) file\(count == 1 ? "" : "s") as \(selectedPurpose.importTitle)."
        scanFolder()
    }

    @discardableResult
    private func importFile(_ file: LocalModelFile, purpose: ModelCapability, silent: Bool = false) -> Bool {
        do {
            let bookmark = try ModelFileAccess.makeBookmarkForVisibleModel(at: file.url)
            let model = try PersistenceController.shared.upsertModel(
                from: bookmark,
                displayName: file.name,
                originalPath: file.url.path,
                fileSize: file.size
            )
            ModelPurposeStore.setPurpose(purpose, for: model)
            setDefaultIfNeeded(model, purpose: purpose)
            if !silent { message = "Imported \(file.name) as \(purpose.importTitle)." }
            errorText = nil
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    private func deleteFile(_ file: LocalModelFile) {
        do {
            let matching = models.filter { $0.originalPath == file.url.path }
            try FileManager.default.removeItem(at: file.url)
            for model in matching {
                clearDefaults(for: model)
                model.managedObjectContext?.delete(model)
            }
            try matching.first?.managedObjectContext?.save()
            message = "Deleted \(file.name)."
            errorText = nil
            scanFolder()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func clearDefaults(for model: ModelReferenceEntity) {
        guard let id = model.id?.uuidString else { return }
        if generationSettings.defaultModelID == id { generationSettings.defaultModelID = "" }
        if generationSettings.defaultImageModelID == id { generationSettings.defaultImageModelID = "" }
        if generationSettings.defaultSpeechToTextModelID == id { generationSettings.defaultSpeechToTextModelID = "" }
        if generationSettings.defaultVoiceOutputModelID == id { generationSettings.defaultVoiceOutputModelID = "" }
    }

    private func setDefaultIfNeeded(_ model: ModelReferenceEntity, purpose: ModelCapability) {
        guard let id = model.id?.uuidString else { return }
        switch purpose {
        case .text: if generationSettings.defaultModelID.isEmpty { generationSettings.defaultModelID = id }
        case .imageGeneration: if generationSettings.defaultImageModelID.isEmpty { generationSettings.defaultImageModelID = id }
        case .speechToText: if generationSettings.defaultSpeechToTextModelID.isEmpty { generationSettings.defaultSpeechToTextModelID = id }
        case .textToSpeech: if generationSettings.defaultVoiceOutputModelID.isEmpty { generationSettings.defaultVoiceOutputModelID = id }
        default: break
        }
    }
}

private struct LocalModelFile: Identifiable, Hashable {
    let url: URL
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}
