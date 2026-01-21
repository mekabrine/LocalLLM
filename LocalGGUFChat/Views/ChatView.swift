
import SwiftUI
import CoreData

struct ChatView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appState: AppState

    @ObservedObject var chat: ChatEntity

    @FetchRequest private var messages: FetchedResults<MessageEntity>

    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generationTask: Task<Void, Never>?
    @State private var activeSelection: MessageEntity?
    @State private var showingSelectionModal = false
    @State private var editingMessage: MessageEntity?
    @State private var showingEditModal = false
    @State private var confirmDeleteFromHere: MessageEntity?
    @State private var showingModelPicker = false
    @State private var errorText: String?
    @State private var showScrollToBottom: Bool = false

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
        .navigationTitle(chat.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingModelPicker = true
                } label: {
                    Image(systemName: "cpu")
                }
                .accessibilityLabel("Model")
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
            generationTask?.cancel()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let model = chat.model {
                            modelHeader(model: model)
                                .padding(.top, 8)
                        }

                        if hasOutdatedMessages {
                            outdatedBanner
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }

                        ForEach(messages) { msg in
                            MessageRow(
                                message: msg,
                                onCopy: { UIPasteboard.general.string = msg.text ?? "" },
                                onSelectText: {
                                    activeSelection = msg
                                    showingSelectionModal = true
                                },
                                onEdit: {
                                    editingMessage = msg
                                    showingEditModal = true
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
                        withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
                }

                if showScrollToBottom {
                    Button {
                        withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) }
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
                Text(errorText).font(.footnote).foregroundColor(.red)
                    .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom, spacing: 10) {
                GlassBackground(cornerRadius: 18)
                    .overlay(
                        GrowingTextEditor(text: $inputText, minHeight: 40, maxHeight: 140) {
                            if canSend { send() }
                        }
                        .padding(.horizontal, 2)
                    )
                    .frame(minHeight: 40)

                Button(action: send) {
                    if isGenerating {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                    }
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(
            GlassBackground(cornerRadius: 0)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        !isGenerating && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.model != nil
    }

    private func send() {
        guard canSend else { return }
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

    private func generateReply(into assistantEntity: MessageEntity, including userEntity: MessageEntity) async {
        do {
            guard let modelEntity = chat.model else {
                throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
            }
            let model = ModelReference(modelEntity)
            let engine = appState.engine(for: model.id)

            try await ModelFileAccess.withSecurityScopedURLAsync(bookmark: model.bookmark) { url in
                try await engine.load(modelURL: url)

                let history = messages.map(Message.init)
                let prompt = PromptBuilder.build(messages: history)
                let stream = await engine.generate(prompt: prompt, config: GenerationConfig(maxTokens: 512))

                var buffer = ""
                var lastPersist = Date()

                for try await token in stream {
                    if Task.isCancelled { break }
                    buffer += token

                    await MainActor.run {
                        assistantEntity.text = buffer
                    }

                    // Persist at ~4Hz to keep UI smooth without thrashing Core Data.
                    if Date().timeIntervalSince(lastPersist) > 0.25 {
                        await MainActor.run { PersistenceController.shared.save() }
                        lastPersist = Date()
                    }
                }

                await MainActor.run {
                    assistantEntity.text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    chat.updatedAt = Date()
                    PersistenceController.shared.save()
                }
            }

            await MainActor.run { isGenerating = false }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private var hasOutdatedMessages: Bool {
        messages.contains(where: { $0.isOutdated })
    }

    @ViewBuilder
    private func modelHeader(model: ModelReferenceEntity) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName ?? "Model")
                    .font(.subheadline).bold()
                Text("\(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var outdatedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("Some messages are marked out of date due to edits.")
                .font(.caption)
            Spacer()
            Button("Clear") {
                // Delete from first outdated message onward.
                if let first = messages.first(where: { $0.isOutdated }) {
                    PersistenceController.shared.deleteFromHere(message: first)
                }
            }
            .font(.caption).bold()
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
            Divider()
            Button(role: .destructive) { onDeleteFromHere() } label: { Label("Delete from Here", systemImage: "trash") }
        }
    }
}
