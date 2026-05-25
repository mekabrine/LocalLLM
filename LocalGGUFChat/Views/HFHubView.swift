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
    @State private var hideGated = true
    @State private var onlyRunnableNow = false
    @State private var maxFileSizeGB = 6
    @State private var showAllFiles = false

    var body: some View {
        NavigationView {
            List {
                searchSection
                recommendedSection
                resultsSection
                filesSection
                collapsedDownloadsSection
                collapsedFiltersSection
                collapsedTokenSection
                collapsedAdvancedSection
            }
            .navigationTitle("HF Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { presentationMode.wrappedValue.dismiss() } }
            }
            .onAppear {
                if purpose == .text || purpose == .fileHelper { onlyRunnableNow = true }
                if repos.isEmpty { runSearch(useDefaultIfEmpty: true) }
            }
        }
    }

    private var searchSection: some View {
        Section(footer: Text("Public models work without a token. Saved files go to LocalLLM/Models and are imported as \(purpose.importTitle).")) {
            HStack {
                TextField(defaultQuery, text: $query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Search") { runSearch(useDefaultIfEmpty: true) }
                    .disabled(isBusy)
            }
            if isBusy { ProgressView("Searching…") }
            if let message { Text(message).font(.caption).foregroundColor(.secondary) }
        }
    }

    private var recommendedSection: some View {
        Section(header: Text("Recommended")) {
            ForEach(recommendedQueries, id: \.self) { item in
                Button {
                    query = item
                    runSearch(useDefaultIfEmpty: false)
                } label: {
                    Label(item, systemImage: "sparkle.magnifyingglass")
                }
            }
        }
    }

    private var resultsSection: some View {
        Section(header: Text("Results"), footer: Text("Tap a repo to view files. Runtime labels show whether LocalLLM can try the file now.")) {
            if filteredRepos.isEmpty && !isBusy {
                Text("No matching public repositories loaded.").foregroundColor(.secondary)
            }
            ForEach(filteredRepos) { repo in
                repoRow(repo)
            }
        }
    }

    private var filesSection: some View {
        Section(header: Text(selectedRepo?.id ?? "Files"), footer: Text(runtimeNotice)) {
            if selectedRepo == nil {
                Text("Choose a result to see files.").foregroundColor(.secondary)
            } else if files.isEmpty && !isBusy {
                Text("No matching files found. Open Filters or Show All Files.").foregroundColor(.secondary)
            } else {
                ForEach(displayedFiles) { file in
                    fileRow(file)
                }
                if files.count > displayedFiles.count {
                    Button(showAllFiles ? "Show Recommended Files" : "Show All Files") { showAllFiles.toggle() }
                }
            }
        }
    }

    private var collapsedDownloadsSection: some View {
        Section {
            DisclosureGroup("Downloads") {
                if store.downloads.isEmpty {
                    Text("No transfers yet.").foregroundColor(.secondary)
                } else {
                    ForEach(store.downloads) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: item.filename).lastPathComponent)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Clear Finished") { store.clearFinished() }
                }
            }
        }
    }

    private var collapsedFiltersSection: some View {
        Section {
            DisclosureGroup("Filters") {
                Toggle("Hide gated/private repos", isOn: $hideGated)
                Toggle("Only files LocalLLM can try now", isOn: $onlyRunnableNow)
                Picker("Max file size", selection: $maxFileSizeGB) {
                    Text("Any").tag(0)
                    Text("1 GB").tag(1)
                    Text("2 GB").tag(2)
                    Text("4 GB").tag(4)
                    Text("6 GB").tag(6)
                }
            }
        }
    }

    private var collapsedTokenSection: some View {
        Section {
            DisclosureGroup("Access Token") {
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
                        runSearch(useDefaultIfEmpty: true)
                    }
                }
                Text("Optional. Public models do not need a token. Use this only for gated or private repos you already have access to.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var collapsedAdvancedSection: some View {
        Section {
            DisclosureGroup("Advanced") {
                Text("Purpose: \(purpose.importTitle)")
                Text("Download folder: LocalLLM/Models")
                Text("Image, speech, voice, and vision files can be saved and organized, but need dedicated runtime backends before they can run.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var filteredRepos: [HuggingFaceRepo] {
        repos.filter { repo in
            if hideGated && (repo.isGated || repo.privateRepo == true) { return false }
            return true
        }
    }

    private var displayedFiles: [HuggingFaceFile] {
        let rows = showAllFiles ? files : Array(files.prefix(8))
        guard maxFileSizeGB > 0 else { return rows }
        let maxBytes = Int64(maxFileSizeGB) * 1_000_000_000
        return rows.filter { ($0.size ?? 0) == 0 || ($0.size ?? 0) <= maxBytes }
    }

    private var recommendedQueries: [String] {
        switch purpose {
        case .text, .fileHelper:
            return ["Qwen2.5 1.5B GGUF Q4_K_M", "TinyLlama GGUF Q4", "Phi GGUF Q4_K_M", "Mistral 7B GGUF Q4_K_M"]
        case .imageGeneration:
            return ["coreml stable diffusion", "sdxl coreml", "flux image model"]
        case .speechToText:
            return ["whisper small", "whisper gguf", "speech to text"]
        case .textToSpeech:
            return ["piper tts", "text to speech model"]
        case .vision:
            return ["llava gguf", "moondream vision", "vision gguf"]
        case .unknown:
            return ["gguf q4", "local model"]
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
        case .text, .fileHelper: return "Prefer smaller GGUF files first. Some newer architectures or IQ/UD quants may need a newer backend."
        default: return "This category can be organized now, but needs a dedicated runtime backend before it can run."
        }
    }

    private func repoRow(_ repo: HuggingFaceRepo) -> some View {
        Button { load(repo) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(repo.id).font(.headline).lineLimit(2)
                    Spacer()
                    if repo.isGated { badge("Gated", color: .orange) }
                }
                Text(repoSummary(repo)).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }
    }

    private func fileRow(_ file: HuggingFaceFile) -> some View {
        let support = file.runtimeSupport(for: purpose)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(file.rfilename).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Download") {
                    guard let selectedRepo else { return }
                    store.download(repoID: selectedRepo.id, file: file, purpose: purpose, token: token)
                }
            }
            HStack(spacing: 6) {
                badge(sizeText(file.size), color: .secondary)
                badge(support.title, color: runtimeColor(support))
            }
            Text(support.detail).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func runSearch(useDefaultIfEmpty: Bool) {
        isBusy = true
        message = nil
        let searchText = useDefaultIfEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultQuery : query
        Task {
            do {
                let results = try await HuggingFaceAPI.searchModels(query: searchText, purpose: purpose, token: token)
                await MainActor.run {
                    repos = results.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
                    files = []
                    selectedRepo = nil
                    message = results.isEmpty ? "No public results found." : nil
                    isBusy = false
                }
            } catch {
                await MainActor.run { message = error.localizedDescription; isBusy = false }
            }
        }
    }

    private func load(_ repo: HuggingFaceRepo) {
        isBusy = true
        selectedRepo = repo
        files = []
        showAllFiles = false
        Task {
            do {
                let info = try await HuggingFaceAPI.repoInfo(repoID: repo.id, token: token)
                await MainActor.run {
                    selectedRepo = info
                    files = filter(info.siblings ?? [])
                    isBusy = false
                }
            } catch {
                await MainActor.run { message = error.localizedDescription; isBusy = false }
            }
        }
    }

    private func filter(_ all: [HuggingFaceFile]) -> [HuggingFaceFile] {
        let allowed: Set<String> = purpose == .text || purpose == .fileHelper ? ["gguf"] : ["gguf", "zip", "mlpackage", "mlmodelc", "safetensors", "onnx"]
        return all.filter { file in
            guard allowed.contains(file.fileExtension) else { return false }
            if onlyRunnableNow && file.runtimeSupport(for: purpose) != .runsNow { return false }
            if maxFileSizeGB > 0, let size = file.size, size > Int64(maxFileSizeGB) * 1_000_000_000 { return false }
            return true
        }
        .sorted { lhs, rhs in
            let lRun = lhs.runtimeSupport(for: purpose) == .runsNow
            let rRun = rhs.runtimeSupport(for: purpose) == .runsNow
            if lRun != rRun { return lRun }
            return (lhs.size ?? Int64.max) < (rhs.size ?? Int64.max)
        }
    }

    private func repoSummary(_ repo: HuggingFaceRepo) -> String {
        var parts: [String] = []
        if let downloads = repo.downloads { parts.append("\(downloads) downloads") }
        if let likes = repo.likes { parts.append("\(likes) likes") }
        if let tags = repo.tags?.prefix(3), !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        return parts.isEmpty ? "Tap to view files." : parts.joined(separator: " • ")
    }

    private func sizeText(_ size: Int64?) -> String {
        guard let size, size > 0 else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func runtimeColor(_ support: ModelRuntimeSupport) -> Color {
        switch support {
        case .runsNow: return .green
        case .tooLarge, .unsupportedFormat: return .red
        case .needsImageBackend, .needsSpeechBackend, .needsVoiceBackend, .needsVisionBackend: return .orange
        case .unknown: return .secondary
        }
    }
}
