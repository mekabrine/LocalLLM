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
                    Button {
                        showingChatInstructions = true
                    } label: {
                        Label("Chat Instructions", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        showingModelPicker = true
                    } label: {
                        Label("Change Model", systemImage: "cpu")
                    }

                    Button {
                        regenerateLastResponse()
                    } label: {
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
            if let activeSelection {
                TextSelectionModal(text: activeSelection.text ?? "")
            }
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
        .onDisappear {
            stopGenerating()
        }
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
                                onRegenerate: {
                                    regenerate(message: msg)
                                },
                                onDeleteFromHere: { confirmDeleteFromHere = msg }
                            )
                            .id(msg.objectID)
                        }

                        Color.clear.frame(height: 8).id("BOTTOM")
                    }
                    .padding(.vertical, 8)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        showScrollToBottom = true
                    }
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
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
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
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(chat.model == nil ? "Select a model first" : "Message LocalLLM")
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
                    Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 38))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!isGenerating && !canSend)
                .accessibilityLabel(isGenerating ? "Stop generating" : "Send")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(
            Color.black
                .opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private var canSend: Bool {
        !isGenerating && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.model != nil
    }

    private var lastUserMessage: MessageEntity? {
        (chat.messages?.array as? [MessageEntity])?.last(where: { $0.role == MessageRole.user.rawValue })
    }

    private func primaryComposerAction() {
        if isGenerating {
            stopGenerating()
        } else {
            send()
        }
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
        showScrollToBottom = false

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        let userMsg = PersistenceController.shared.appendMessage(chat: chat, role: .user, text: trimmed)
        let assistantMsg = PersistenceController.shared.appendMessage(chat: chat, role: .assistant, text: "")

        isGenerating = true

        generationTask?.cancel()
        generationTask = Task { await generateReply(into: assistantMsg, including: userMsg) }
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
        generationTask?.cancel()
        generationTask = Task { await generateReply(into: assistantMsg, including: previousUser) }
    }

    private func generateReply(into assistantEntity: MessageEntity, including userEntity: MessageEntity) async {
        var displayDriver: ResponseDisplayDriver?

        do {
            guard let modelEntity = chat.model else {
                throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
            }

            let model = ModelReference(modelEntity)
            let engine = appState.engine(for: model.id)
            let effective = await MainActor.run { generationSettings.effectiveSettings(forModelSize: modelEntity.fileSize) }
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

            let finalOutput = try await ModelFileAccess.withSecurityScopedURLAsync(bookmark: model.bookmark) { url -> String in
                try await engine.load(modelURL: url)

                let prompt = PromptBuilder.build(
                    messages: history,
                    systemMessage: systemMessage,
                    effectiveSettings: effective
                )
                let stream = engine.generate(prompt: prompt, config: effective.config)

                var rawBuffer = ""
                var visibleBuffer = ""
                var lastPersist = Date()

                for try await token in stream {
                    if Task.isCancelled { break }
                    rawBuffer += token
                    let filtered = GenerationOutputFilter.filteredText(from: rawBuffer, userStops: effective.config.stop)
                    visibleBuffer = filtered.text

                    await MainActor.run {
                        displayDriver?.updateTarget(visibleBuffer)
                    }

                    if filtered.shouldStop {
                        break
                    }

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
            await MainActor.run {
                displayDriver?.cancel()
                errorText = error.localizedDescription
                isGenerating = false
                generationTask = nil
            }
        }
    }

    private func thinkingText(for mode: ReasoningMode, display: ReasoningDisplayMode) -> String {
        guard display != .hidden else { return "" }

        switch mode {
        case .deep:
            return "Thinking deeply…"
        case .balanced:
            return "Thinking…"
        case .fast, .auto:
            return "Thinking…"
        case .off:
            return ""
        }
    }

    private var hasOutdatedMessages: Bool {
        messages.contains(where: { $0.isOutdated })
    }

    @ViewBuilder
    private func modelHeader(model: ModelReferenceEntity) -> some View {
        let profile = GenerationProfile.profile(forFileSize: model.fileSize)
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName ?? "Model")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file)) • Auto: \(profile.title)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(generationSettings.generationMode == .auto ? "Auto" : "Manual")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.16)))
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
        ChatBubble(
            text: message.text ?? "",
            isUser: message.role == MessageRole.user.rawValue,
            isOutdated: message.isOutdated
        )
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
