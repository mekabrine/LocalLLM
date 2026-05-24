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
                Section(header: Text("Search"), footer: Text("Saved files go to LocalLLM/Models and are imported as \(purpose.importTitle).")) {
                    TextField(defaultQuery, text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("Search Models") { runSearch() }
                    if isBusy { ProgressView() }
                    if let message { Text(message).font(.caption).foregroundColor(.secondary) }
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
                    ForEach(repos) { repo in
                        Button(repo.id) { load(repo) }
                    }
                }

                Section(header: Text(selectedRepo?.id ?? "Files"), footer: Text(runtimeNotice)) {
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
        case .text, .fileHelper: return "Text GGUF files can be tried with the current text backend."
        default: return "This category can be organized now, but needs a dedicated runtime backend before it can run."
        }
    }

    private func runSearch() {
        isBusy = true
        message = nil
        Task {
            do {
                let results = try await HuggingFaceService.searchModels(query: query, purpose: purpose, token: token)
                await MainActor.run { repos = results; files = []; selectedRepo = nil; isBusy = false }
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
                let info = try await HuggingFaceService.repoInfo(repoID: repo.id, token: token)
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
