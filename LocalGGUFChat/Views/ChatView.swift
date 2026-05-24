import SwiftUI
import CoreData
import UIKit

struct ChatView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var generationSettings: GenerationSettings

    @ObservedObject var chat: ChatEntity

    @FetchRequest private var messages: FetchedResults<MessageEntity>

    @State private var inputText: String = ""
    @State private var composerTextHeight: CGFloat = 42
    @State private var isGenerating: Bool = false
    @State private var generationTask: Task<Void, Never>?
    @State private var activeSelection: MessageEntity?
    @State private var showingSelectionModal = false
    @State private var editingMessage: MessageEntity?
    @State private var showingEditModal = false
    @State private var confirmDeleteFromHere: MessageEntity?
    @State private var showingModelPicker = false
    @State private var showingChatInstructions = false
    @State private var showingFilePicker = false
    @State private var pendingAttachments: [PendingFileAttachment] = []
    @State private var generateImageInsteadOfText: Bool = false
    @State private var lastDiagnostic: RuntimeDiagnostic?
    @State private var showingDiagnostic = false
    @State private var errorText: String?
    @State private var showScrollToBottom: Bool = false

    private let composerMinHeight: CGFloat = 42
    private let composerMaxHeight: CGFloat = 210

    init(chat: ChatEntity) {
        self.chat = chat
        _messages = FetchRequest<MessageEntity>(
            sortDescriptors: [NSSortDescriptor(keyPath: \MessageEntity.createdAt, ascending: true)],
            predicate: NSPredicate(format: "chat == %@", chat),
            animation: .default
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(chat.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingChatInstructions = true } label: {
                        Label("Chat Instructions", systemImage: "slider.horizontal.3")
                    }

                    Button { showingModelPicker = true } label: {
                        Label("Change Model", systemImage: "cpu")
                    }

                    Button {
                        if let diagnostic = lastDiagnostic {
                            UIPasteboard.general.string = diagnostic.copyText
                        }
                    } label: {
                        Label("Copy Last Diagnostic", systemImage: "doc.on.doc")
                    }
                    .disabled(lastDiagnostic == nil)

                    Button { regenerateLastResponse() } label: {
                        Label("Regenerate Last", systemImage: "arrow.clockwise")
                    }
                    .disabled(isGenerating || lastUserMessage == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Chat options")
            }
        }
        .sheet(isPresented: $showingSelectionModal) {
            if let activeSelection { TextSelectionModal(text: activeSelection.text ?? "") }
        }
        .sheet(isPresented: $showingEditModal) {
            if let editingMessage {
                EditMessageModal(message: editingMessage) {
                    PersistenceController.shared.markOutdatedAfter(message: editingMessage)
                }
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerModal(selected: chat.model) { newModel in
                chat.model = newModel
                chat.updatedAt = Date()
                PersistenceController.shared.save()
            }
            .environment(\.managedObjectContext, moc)
        }
        .sheet(isPresented: $showingChatInstructions) {
            ChatInstructionsView(chat: chat)
                .environmentObject(generationSettings)
        }
        .sheet(isPresented: $showingFilePicker) {
            FileDocumentPicker(allowsMultipleSelection: true) { result in
                showingFilePicker = false
                handleFilePick(result)
            }
        }
        .sheet(isPresented: $showingDiagnostic) {
            if let lastDiagnostic {
                RuntimeDiagnosticView(diagnostic: lastDiagnostic)
            }
        }
        .alert(item: $confirmDeleteFromHere) { msg in
            Alert(
                title: Text("Delete from here?"),
                message: Text("This will delete the selected message and everything after it."),
                primaryButton: .destructive(Text("Delete")) {
                    PersistenceController.shared.deleteFromHere(message: msg)
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            generateImageInsteadOfText = generationSettings.imageGenerationEnabledByDefault
        }
        .onDisappear { stopGenerating() }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let model = chat.model {
                            modelHeader(model: model)
                                .padding(.top, 10)
                        }

                        if hasOutdatedMessages {
                            outdatedBanner
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }

                        ForEach(messages) { msg in
                            MessageRow(
                                message: msg,
                                onCopy: {
                                    UIPasteboard.general.string = msg.text ?? ""
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                onSelectText: {
                                    activeSelection = msg
                                    showingSelectionModal = true
                                },
                                onEdit: {
                                    editingMessage = msg
                                    showingEditModal = true
                                },
                                onRegenerate: { regenerate(message: msg) },
                                onDeleteFromHere: { confirmDeleteFromHere = msg }
                            )
                            .id(msg.objectID)
                        }

                        Color.clear.frame(height: 8).id("BOTTOM")
                    }
                    .padding(.vertical, 8)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in showScrollToBottom = true }
                )
                .onChange(of: messages.count) { _ in
                    if !showScrollToBottom {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                    }
                }
                .onChange(of: messages.last?.text) { _ in
                    if !showScrollToBottom {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                }

                if showScrollToBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                        showScrollToBottom = false
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.headline)
                            .padding(12)
                            .background(GlassBackground(cornerRadius: 18))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let errorText {
                Button {
                    if lastDiagnostic != nil { showingDiagnostic = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorText)
                            .lineLimit(2)
                        Spacer()
                        if lastDiagnostic != nil { Image(systemName: "chevron.up") }
                    }
                    .font(.footnote)
                    .foregroundColor(StudioTheme.danger)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
            }

            if !pendingAttachments.isEmpty {
                attachmentsStrip
            }

            composerModeRow

            HStack(alignment: .bottom, spacing: 10) {
                Button { showingFilePicker = true } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach file")

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(generateImageInsteadOfText ? 0.28 : 0.12), lineWidth: 1)
                        )

                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholderText)
                            .foregroundColor(.secondary)
                            .padding(.leading, 16)
                            .padding(.top, 13)
                    }

                    GrowingTextEditor(
                        text: $inputText,
                        measuredHeight: $composerTextHeight,
                        minHeight: composerMinHeight,
                        maxHeight: composerMaxHeight
                    ) {
                        if canSend { send() }
                    }
                    .frame(height: composerTextHeight)
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                }
                .frame(height: composerTextHeight + 8)

                Button(action: primaryComposerAction) {
                    Image(systemName: sendButtonIcon)
                        .font(.system(size: 38))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!isGenerating && !canSend)
                .accessibilityLabel(isGenerating ? "Stop generating" : "Send")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .padding(.top, 10)
        .background(Color.black.opacity(0.96).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private var composerModeRow: some View {
        HStack(spacing: 14) {
            Button { showingFilePicker = true } label: {
                Label("Files", systemImage: "doc.badge.plus")
            }

            Button {
                errorText = "Voice input UI is ready. Local speech-to-text backend support still needs to be connected."
            } label: {
                Label("Voice", systemImage: "mic")
            }

            Toggle(isOn: $generateImageInsteadOfText) {
                Label("Generate Image", systemImage: "photo")
            }
            .toggleStyle(.button)
            .tint(.accentColor)

            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(StudioTheme.secondaryText)
        .padding(.horizontal, 16)
    }

    private var attachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachment.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(attachment.summary)
                                .font(.caption2)
                                .foregroundColor(StudioTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(StudioTheme.secondaryText)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(StudioTheme.surface))
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !isGenerating && chat.model != nil && (hasText || !pendingAttachments.isEmpty)
    }

    private var placeholderText: String {
        if generateImageInsteadOfText { return "Describe the image to generate" }
        return chat.model == nil ? "Select a model first" : "Message LocalLLM"
    }

    private var sendButtonIcon: String {
        if isGenerating { return "stop.circle.fill" }
        return generateImageInsteadOfText ? "sparkles" : "arrow.up.circle.fill"
    }

    private var lastUserMessage: MessageEntity? {
        (chat.messages?.array as? [MessageEntity])?.last(where: { $0.role == MessageRole.user.rawValue })
    }

    private func primaryComposerAction() {
        if isGenerating { stopGenerating() } else { send() }
    }

    private func stopGenerating() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func send() {
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        errorText = nil
        lastDiagnostic = nil
        showScrollToBottom = false

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageText = composedUserMessage(typedText: trimmed)
        inputText = ""
        pendingAttachments.removeAll()

        let userMsg = PersistenceController.shared.appendMessage(chat: chat, role: .user, text: messageText)

        if generateImageInsteadOfText {
            createImageGenerationPlaceholder(for: userMsg, prompt: trimmed)
            return
        }

        let assistantMsg = PersistenceController.shared.appendMessage(chat: chat, role: .assistant, text: "")
        isGenerating = true
        generationTask?.cancel()
        generationTask = Task { await generateReply(into: assistantMsg, including: userMsg) }
    }

    private func createImageGenerationPlaceholder(for userMsg: MessageEntity, prompt: String) {
        let selectedImageModel = generationSettings.defaultImageModelID.isEmpty ? "No image model selected" : "Selected image model"
        let response = """
        Image generation request queued.

        Prompt: \(prompt.isEmpty ? "Attached file context" : prompt)
        Model: \(selectedImageModel)
        Size: \(generationSettings.imageSize.title)
        Quality: \(generationSettings.imageQuality.title)

        Image generation UI and routing are ready. A dedicated local image backend still needs to be connected before this can render pixels.
        """
        PersistenceController.shared.appendMessage(chat: chat, role: .assistant, text: response)
    }

    private func composedUserMessage(typedText: String) -> String {
        guard !pendingAttachments.isEmpty else { return typedText }
        let fileText = pendingAttachments.map { attachment in
            """
            Attached file: \(attachment.title)
            \(attachment.summary)

            \(attachment.text)
            """
        }.joined(separator: "\n\n---\n\n")

        if typedText.isEmpty { return "Please use the attached file context.\n\n\(fileText)" }
        return "\(typedText)\n\nFile context:\n\(fileText)"
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            var newAttachments: [PendingFileAttachment] = []
            for url in urls {
                let extracted = try ChatFileAttachmentExtractor.extractText(from: url)
                newAttachments.append(PendingFileAttachment(title: extracted.title, summary: extracted.summary, text: extracted.text))
            }
            pendingAttachments.append(contentsOf: newAttachments)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func regenerateLastResponse() {
        guard let lastUserMessage else { return }
        let ordered = chat.messages?.array as? [MessageEntity] ?? []
        if let last = ordered.last, last.role == MessageRole.assistant.rawValue {
            PersistenceController.shared.deleteFromHere(message: last)
        }

        let assistantMsg = PersistenceController.shared.appendMessage(chat: chat, role: .assistant, text: "")
        isGenerating = true
        errorText = nil
        lastDiagnostic = nil
        generationTask?.cancel()
        generationTask = Task { await generateReply(into: assistantMsg, including: lastUserMessage) }
    }

    private func regenerate(message: MessageEntity) {
        guard !isGenerating, message.role == MessageRole.assistant.rawValue else { return }
        guard let ordered = chat.messages?.array as? [MessageEntity],
              let index = ordered.firstIndex(of: message),
              let previousUser = ordered[..<index].reversed().first(where: { $0.role == MessageRole.user.rawValue }) else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        PersistenceController.shared.deleteFromHere(message: message)
        let assistantMsg = PersistenceController.shared.appendMessage(chat: chat, role: .assistant, text: "")
        isGenerating = true
        errorText = nil
        lastDiagnostic = nil
        generationTask?.cancel()
        generationTask = Task { await generateReply(into: assistantMsg, including: previousUser) }
    }

    private func generateReply(into assistantEntity: MessageEntity, including userEntity: MessageEntity) async {
        var displayDriver: ResponseDisplayDriver?
        var diagnosticModel: ModelReferenceEntity?
        var diagnosticSettings: EffectiveGenerationSettings?
        var stage = "Preparing generation"

        do {
            guard let modelEntity = chat.model else {
                throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
            }

            diagnosticModel = modelEntity
            let model = ModelReference(modelEntity)
            let engine = appState.engine(for: model.id)
            let effective = await MainActor.run { generationSettings.effectiveSettings(forModelSize: modelEntity.fileSize) }
            diagnosticSettings = effective
            let systemMessage = await MainActor.run { generationSettings.combinedSystemMessage(for: chat.id) }
            let liveDisplay = await MainActor.run { generationSettings.liveDisplayMode }
            let typingSpeed = await MainActor.run { generationSettings.typingCharactersPerSecond }
            let history = await MainActor.run { messages.map(Message.init) }

            await MainActor.run {
                assistantEntity.text = thinkingText(for: effective.reasoningMode, display: effective.reasoningDisplay)
                displayDriver = ResponseDisplayDriver(
                    message: assistantEntity,
                    mode: liveDisplay,
                    charactersPerSecond: typingSpeed
                )
            }

            stage = "Checking file access"
            let finalOutput = try await ModelFileAccess.withSecurityScopedURLAsync(bookmark: model.bookmark) { url -> String in
                stage = "Loading backend"
                try await engine.load(modelURL: url)

                stage = "Building prompt"
                let prompt = PromptBuilder.build(
                    messages: history,
                    systemMessage: systemMessage,
                    effectiveSettings: effective
                )
                let stream = engine.generate(prompt: prompt, config: effective.config)

                var rawBuffer = ""
                var visibleBuffer = ""
                var lastPersist = Date()

                stage = "Streaming response"
                for try await token in stream {
                    if Task.isCancelled { break }
                    rawBuffer += token
                    let filtered = GenerationOutputFilter.filteredText(from: rawBuffer, userStops: effective.config.stop)
                    visibleBuffer = filtered.text

                    await MainActor.run { displayDriver?.updateTarget(visibleBuffer) }

                    if filtered.shouldStop { break }

                    if Date().timeIntervalSince(lastPersist) > 0.35 {
                        await MainActor.run { PersistenceController.shared.save() }
                        lastPersist = Date()
                    }
                }

                return visibleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let textToSave = finalOutput.isEmpty ? "No response." : finalOutput
            await displayDriver?.finish(finalText: textToSave)

            await MainActor.run {
                chat.updatedAt = Date()
                PersistenceController.shared.save()
                isGenerating = false
                generationTask = nil
            }
        } catch is CancellationError {
            await MainActor.run {
                displayDriver?.cancel()
                isGenerating = false
                generationTask = nil
                PersistenceController.shared.save()
            }
        } catch {
            let diagnostic = RuntimeDiagnostic.from(error: error, stage: stage, model: diagnosticModel, settings: diagnosticSettings)
            await MainActor.run {
                displayDriver?.cancel()
                lastDiagnostic = diagnostic
                showingDiagnostic = generationSettings.detailedErrors
                errorText = generationSettings.detailedErrors ? diagnostic.shortMessage : error.localizedDescription
                assistantEntity.text = ""
                isGenerating = false
                generationTask = nil
            }
        }
    }

    private func thinkingText(for mode: ReasoningMode, display: ReasoningDisplayMode) -> String {
        guard display != .hidden else { return "" }
        switch mode {
        case .deep: return "Thinking deeply…"
        case .balanced, .fast, .auto: return "Thinking…"
        case .off: return ""
        }
    }

    private var hasOutdatedMessages: Bool { messages.contains(where: { $0.isOutdated }) }

    @ViewBuilder
    private func modelHeader(model: ModelReferenceEntity) -> some View {
        let profile = GenerationProfile.profile(forFileSize: model.fileSize)
        let info = ModelCapabilityInfo.infer(name: model.displayName, fileSize: model.fileSize)
        HStack(spacing: 12) {
            StudioIconCircle(systemName: info.capability.systemImage, color: .accentColor, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName ?? "Model")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)) • Auto: \(profile.title)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            StudioBadge(title: generationSettings.generationMode == .auto ? "Auto" : "Manual", color: .accentColor)
        }
        .padding(14)
        .background(GlassBackground(cornerRadius: 20))
        .padding(.horizontal, 14)
    }

    private var outdatedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("Some messages are marked out of date due to edits.")
                .font(.caption)
            Spacer()
            Button("Clear") {
                if let first = messages.first(where: { $0.isOutdated }) {
                    PersistenceController.shared.deleteFromHere(message: first)
                }
            }
            .font(.caption.weight(.bold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

private struct MessageRow: View {
    let message: MessageEntity
    let onCopy: () -> Void
    let onSelectText: () -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onDeleteFromHere: () -> Void

    var body: some View {
        ChatBubble(text: message.text ?? "", isUser: message.role == MessageRole.user.rawValue, isOutdated: message.isOutdated)
            .contextMenu {
                Button { onCopy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { onSelectText() } label: { Label("Select Text", systemImage: "selection.pin.in.out") }
                Button { onEdit() } label: { Label("Edit Message", systemImage: "pencil") }
                if message.role == MessageRole.assistant.rawValue {
                    Button { onRegenerate() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                }
                Divider()
                Button(role: .destructive) { onDeleteFromHere() } label: { Label("Delete from Here", systemImage: "trash") }
            }
    }
}

private struct RuntimeDiagnosticView: View {
    @Environment(\.presentationMode) private var presentationMode
    let diagnostic: RuntimeDiagnostic

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StudioGlassCard(cornerRadius: 18, borderColor: StudioTheme.danger.opacity(0.35)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Likely Cause", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundColor(StudioTheme.danger)
                            Text(diagnostic.likelyCause)
                                .font(.subheadline)
                        }
                    }

                    diagnosticsBlock(title: "What Happened", rows: [
                        ("Stage", diagnostic.stage),
                        ("Raw Error", diagnostic.rawError)
                    ])

                    diagnosticsBlock(title: "Model", rows: [
                        ("Name", diagnostic.modelName),
                        ("Size", diagnostic.modelSize),
                        ("Compatibility", diagnostic.compatibility)
                    ])

                    diagnosticsBlock(title: "Settings", rows: [("Current", diagnostic.settingsSummary)])

                    StudioGlassCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What to Try")
                                .font(.headline)
                            Text("Use a smaller model, lower context/output, enable Large Model Survival Mode, choose a different quantization, or use remote/server mode for 30B+ models.")
                                .font(.subheadline)
                                .foregroundColor(StudioTheme.secondaryText)
                        }
                    }
                }
                .padding(18)
            }
            .background(StudioTheme.background.ignoresSafeArea())
            .navigationTitle("Model Load Error")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { presentationMode.wrappedValue.dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Copy") { UIPasteboard.general.string = diagnostic.copyText } }
            }
        }
    }

    private func diagnosticsBlock(title: String, rows: [(String, String)]) -> some View {
        StudioGlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(StudioTheme.secondaryText)
                        Text(row.1)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
