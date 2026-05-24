import SwiftUI

struct HFHubView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var store = HuggingFaceDownloadStore.shared

    let purpose: ModelCapability

    @State private var token = HuggingFaceTokenStore.readToken()
    @State private var query = ""
    @State private var repos: [HuggingFaceRepo] = []
    @State private var selectedRepo: HuggingFaceRepo?
    @State private var files: [HuggingFaceFile] = []
    @State private var isBusy = false
    @State private var message: String?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Search"), footer: Text("Saved files go to LocalLLM/Models and are imported as \(purpose.importTitle). Public models do not need a token.")) {
                    TextField(defaultQuery, text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Search Models") { runSearch() }
                    if isBusy { ProgressView() }
                    if let message { Text(message).font(.caption).foregroundColor(.secondary) }
                }

                Section(header: Text("Access Token"), footer: Text("Optional. Public models work without a token. Save a read token only for gated or private models.")) {
                    SecureField("hf_...", text: $token)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    HStack {
                        Button("Save Token") {
                            HuggingFaceTokenStore.saveToken(token)
                            message = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Token cleared. Public search will be used." : "Token saved."
                        }
                        Spacer()
                        Button("Use Public Only") {
                            token = ""
                            HuggingFaceTokenStore.deleteToken()
                            runSearch()
                        }
                    }
                }

                Section(header: Text("Transfers")) {
                    if store.downloads.isEmpty {
                        Text("No transfers yet.").foregroundColor(.secondary)
                    } else {
                        ForEach(store.downloads) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.filename).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(item.detail).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Button("Clear Finished") { store.clearFinished() }
                    }
                }

                Section(header: Text("Repositories")) {
                    if repos.isEmpty && !isBusy {
                        Text("No repositories loaded yet.").foregroundColor(.secondary)
                    }
                    ForEach(repos) { repo in
                        Button(repo.id) { load(repo) }
                    }
                }

                Section(header: Text(selectedRepo?.id ?? "Files"), footer: Text(runtimeNotice)) {
                    if selectedRepo != nil && files.isEmpty && !isBusy {
                        Text("No matching files found in this repository.").foregroundColor(.secondary)
                    }
                    ForEach(files) { file in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(file.rfilename).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Save") {
                                    if let selectedRepo {
                                        store.download(repoID: selectedRepo.id, file: file, purpose: purpose, token: token)
                                    }
                                }
                            }
                            Text(file.runtimeSupport(for: purpose).title)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Hugging Face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Done") { presentationMode.wrappedValue.dismiss() } } }
            .onAppear { if repos.isEmpty { runSearch() } }
        }
    }

    private var defaultQuery: String {
        switch purpose {
        case .text, .fileHelper: return "gguf q4"
        case .imageGeneration: return "coreml stable diffusion"
        case .speechToText: return "whisper"
        case .textToSpeech: return "piper tts"
        case .vision: return "vision model"
        case .unknown: return "gguf"
        }
    }

    private var runtimeNotice: String {
        switch purpose {
        case .text, .fileHelper: return "Text GGUF files can be tried with the current text backend. Newer Gemma/Qwen GGUF files may still need a newer backend."
        default: return "This category can be organized now, but needs a dedicated runtime backend before it can run."
        }
    }

    private func runSearch() {
        isBusy = true
        message = nil
        Task {
            do {
                let results = try await HuggingFaceAPI.searchModels(query: query, purpose: purpose, token: token)
                await MainActor.run { repos = results; files = []; selectedRepo = nil; message = results.isEmpty ? "No public results found." : nil; isBusy = false }
            } catch {
                await MainActor.run { message = error.localizedDescription; isBusy = false }
            }
        }
    }

    private func load(_ repo: HuggingFaceRepo) {
        isBusy = true
        selectedRepo = repo
        files = []
        Task {
            do {
                let info = try await HuggingFaceAPI.repoInfo(repoID: repo.id, token: token)
                await MainActor.run { selectedRepo = info; files = filter(info.siblings ?? []); isBusy = false }
            } catch {
                await MainActor.run { message = error.localizedDescription; isBusy = false }
            }
        }
    }

    private func filter(_ all: [HuggingFaceFile]) -> [HuggingFaceFile] {
        let allowed: Set<String> = purpose == .text || purpose == .fileHelper ? ["gguf"] : ["gguf", "zip", "mlpackage", "mlmodelc", "safetensors", "onnx"]
        return all.filter { allowed.contains($0.fileExtension) }.sorted { ($0.size ?? Int64.max) < ($1.size ?? Int64.max) }
    }
}
