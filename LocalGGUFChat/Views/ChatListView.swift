import SwiftUI
import CoreData

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var generationSettings: GenerationSettings

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ModelReferenceEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var models: FetchedResults<ModelReferenceEntity>

    @State private var showingNewChat = false
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        modelStatusCard
                        newChatButton
                        recentChats
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewChat = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("New Chat")
                }
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView()
                    .environment(\.managedObjectContext, moc)
                    .environmentObject(appState)
                    .environmentObject(generationSettings)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(\.managedObjectContext, moc)
                    .environmentObject(generationSettings)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.accentColor)
                Text("LocalLLM")
                    .font(.largeTitle.weight(.bold))
            }

            Text("Private AI, running on your device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelStatusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: defaultModel == nil ? "cpu" : "cpu.fill")
                .font(.title2)
                .foregroundColor(defaultModel == nil ? .secondary : .accentColor)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                Text(defaultModel == nil ? "No default model" : "Default model")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(defaultModel?.displayName ?? "Add a GGUF model to start")
                    .font(.headline)
                    .lineLimit(1)

                if let defaultModel {
                    Text(ByteCountFormatter.string(fromByteCount: defaultModel.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(GlassBackground(cornerRadius: 24))
    }

    private var newChatButton: some View {
        Button {
            showingNewChat = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Chat")
                        .font(.headline)
                    Text(defaultModel == nil ? "Choose a model first" : "Start with your local model")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.accentColor)
            )
        }
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Chats")
                    .font(.headline)
                Spacer()
                if !chats.isEmpty {
                    Text("\(chats.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .foregroundColor(.secondary)
                }
            }

            if chats.isEmpty {
                EmptyDashboardCard()
            } else {
                ForEach(chats) { chat in
                    NavigationLink(destination: ChatView(chat: chat)) {
                        ChatCard(chat: chat)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(chat)
                        } label: {
                            Label("Delete Chat", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var defaultModel: ModelReferenceEntity? {
        guard !generationSettings.defaultModelID.isEmpty else { return models.first }
        return models.first(where: { $0.id?.uuidString == generationSettings.defaultModelID }) ?? models.first
    }

    private func delete(_ chat: ChatEntity) {
        moc.delete(chat)
        PersistenceController.shared.save()
    }
}

private struct ChatCard: View {
    let chat: ChatEntity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(chat.title ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(DateFormatters.shortDateTime.string(from: chat.updatedAt ?? chat.createdAt ?? Date()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(lastMessagePreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                if let model = chat.model?.displayName {
                    Label(model, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(GlassBackground(cornerRadius: 22))
    }

    private var lastMessagePreview: String {
        guard let ordered = chat.messages?.array as? [MessageEntity],
              let last = ordered.last,
              let text = last.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No messages yet"
        }
        return text
    }
}

private struct EmptyDashboardCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text("No chats yet")
                .font(.headline)
            Text("Create a chat, pick a GGUF model, and start talking offline.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(GlassBackground(cornerRadius: 24))
    }
}
