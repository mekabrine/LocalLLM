import SwiftUI
import CoreData

struct OnboardingView: View {
    @EnvironmentObject private var generationSettings: GenerationSettings

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    let onFinish: () -> Void

    @State private var page = 0
    @State private var scanStatus: String?
    @State private var errorText: String?

    private let pageCount = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    modelFolderPage.tag(1)
                    scanPage.tag(2)
                    defaultModelPage.tag(3)
                    behaviorPage.tag(4)
                    startPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
        .foregroundColor(.white)
        .onAppear {
            ensureVisibleModelsFolderExists()
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? Color.accentColor : Color.white.opacity(0.16))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var welcomePage: some View {
        OnboardingPage {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundColor(.accentColor)
                    .frame(width: 104, height: 104)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(spacing: 8) {
                    Text("Welcome to LocalLLM")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Private AI that runs on your iPhone with local GGUF models.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var modelFolderPage: some View {
        OnboardingPage(title: "Add a GGUF model", subtitle: "Large model files work best when placed directly in the app's visible folder.") {
            VStack(spacing: 14) {
                OnboardingFeature(icon: "folder.fill", title: "Open Files", subtitle: "Go to On My iPhone → LocalGGUFChat → Models.")
                OnboardingFeature(icon: "doc.fill", title: "Move your .gguf file", subtitle: "Put the model file in the Models folder instead of copying it through the picker.")
                OnboardingFeature(icon: "lock.shield.fill", title: "Private by default", subtitle: "Your chats and models stay on this device.")
            }
        }
    }

    private var scanPage: some View {
        OnboardingPage(title: "Scan models", subtitle: "After adding a .gguf file, scan the folder so LocalLLM can use it.") {
            VStack(spacing: 14) {
                Button {
                    scanVisibleModelsFolder()
                } label: {
                    Label("Scan Models Folder", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.accentColor))
                        .foregroundColor(.white)
                }

                if let scanStatus {
                    Text(scanStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                modelCountCard
            }
        }
    }

    private var defaultModelPage: some View {
        OnboardingPage(title: "Choose a default model", subtitle: "New chats can automatically start with your selected model.") {
            VStack(spacing: 14) {
                if models.isEmpty {
                    OnboardingFeature(icon: "exclamationmark.triangle.fill", title: "No models found yet", subtitle: "You can finish setup now and add a model later in Settings.")
                } else {
                    Picker("Default model", selection: $generationSettings.defaultModelID) {
                        Text("Use first available").tag("")
                        ForEach(models) { model in
                            Text(model.displayName ?? "Model").tag(model.id?.uuidString ?? "")
                        }
                    }
                    .pickerStyle(.inline)
                    .padding(12)
                    .background(GlassBackground(cornerRadius: 20))
                }
            }
        }
    }

    private var behaviorPage: some View {
        OnboardingPage(title: "Choose behavior", subtitle: "Auto is recommended. It shortens prompts for small models to reduce fake conversation output.") {
            VStack(spacing: 14) {
                Picker("Generation", selection: $generationSettings.generationMode) {
                    ForEach(GenerationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Prompt Style", selection: $generationSettings.promptStyle) {
                    ForEach(PromptStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Picker("Reasoning", selection: $generationSettings.reasoningMode) {
                    ForEach(ReasoningMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("Live Display", selection: $generationSettings.liveDisplayMode) {
                    ForEach(LiveDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(16)
            .background(GlassBackground(cornerRadius: 24))
        }
    }

    private var startPage: some View {
        OnboardingPage(title: "Ready to chat", subtitle: "You can change models, behavior, reasoning, and live display later in Settings.") {
            VStack(spacing: 14) {
                OnboardingFeature(icon: models.isEmpty ? "cpu" : "cpu.fill", title: modelSummaryTitle, subtitle: modelSummarySubtitle)
                OnboardingFeature(icon: "slider.horizontal.3", title: "Auto behavior", subtitle: "Small models use simpler prompts and shorter output by default.")
                OnboardingFeature(icon: "keyboard", title: "Smooth input", subtitle: "The message box grows up to five lines, then scrolls.")
            }
        }
    }

    private var modelCountCard: some View {
        VStack(spacing: 6) {
            Text(models.isEmpty ? "No models registered" : "\(models.count) model\(models.count == 1 ? "" : "s") registered")
                .font(.headline)
            Text(models.isEmpty ? "Finish setup now, or scan after adding a model." : "You can pick a default model on the next screen.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(GlassBackground(cornerRadius: 20))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if page > 0 {
                    Button("Back") {
                        withAnimation(.easeOut(duration: 0.2)) { page -= 1 }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
                }

                Button(page == pageCount - 1 ? "Start" : "Next") {
                    if page == pageCount - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { page += 1 }
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.accentColor))
            }

            Button("Skip for now") {
                onFinish()
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private var modelSummaryTitle: String {
        guard let model = selectedOrFirstModel else { return "No model selected" }
        return model.displayName ?? "Selected model"
    }

    private var modelSummarySubtitle: String {
        guard let model = selectedOrFirstModel else { return "Add a GGUF model from Settings when you are ready." }
        let profile = GenerationProfile.profile(forFileSize: model.fileSize)
        return "\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)) • \(profile.title)"
    }

    private var selectedOrFirstModel: ModelReferenceEntity? {
        guard !generationSettings.defaultModelID.isEmpty else { return models.first }
        return models.first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) ?? models.first
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
                scanStatus = "No .gguf files found in LocalGGUFChat/Models."
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

            scanStatus = count == 1 ? "Added 1 model." : "Added \(count) models."
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 34)

                if let title {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        if let subtitle {
                            Text(subtitle)
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                content

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OnboardingFeature: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(GlassBackground(cornerRadius: 20))
    }
}
