import SwiftUI
import CoreData
import UIKit

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
    @State private var showingImporter = false
    @State private var dashboardStatus: String?
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        setupChecklist
                        modelStatusCard
                        dashboardActions
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
            .sheet(isPresented: $showingImporter) {
                ModelDocumentPicker(allowsMultipleSelection: true) { result in
                    showingImporter = false
                    importModels(result)
                }
            }
            .onAppear {
                ensureVisibleModelsFolderExists()
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

    private var setupChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup")
                .font(.headline)

            SetupChecklistRow(isComplete: true, title: "App installed", subtitle: "LocalLLM is ready.")
            SetupChecklistRow(isComplete: true, title: "Models folder ready", subtitle: "Files → On My iPhone → LocalGGUFChat → Models")
            SetupChecklistRow(isComplete: !models.isEmpty, title: "Add GGUF model", subtitle: models.isEmpty ? "Move a .gguf file into the Models folder or import one." : "\(models.count) model\(models.count == 1 ? "" : "s") available.")
            SetupChecklistRow(isComplete: defaultModel != nil, title: "Choose default model", subtitle: defaultModel?.displayName ?? "Auto-selects the first model until you choose one.")
            SetupChecklistRow(isComplete: !chats.isEmpty, title: "Start first chat", subtitle: chats.isEmpty ? "Create a chat when a model is ready." : "\(chats.count) chat\(chats.count == 1 ? "" : "s") created.")

            if let dashboardStatus {
                Text(dashboardStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(GlassBackground(cornerRadius: 24))
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
                    let profile = GenerationProfile.profile(forFileSize: defaultModel.fileSize)
                    Text("\(ByteCountFormatter.string(fromByteCount: defaultModel.fileSize, countStyle: .file)) • Auto: \(profile.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Scan the Models folder after adding a file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(GlassBackground(cornerRadius: 24))
    }

    private var dashboardActions: some View {
        VStack(spacing: 12) {
            newChatButton

            HStack(spacing: 12) {
                SecondaryDashboardButton(icon: "folder.badge.gearshape", title: "Scan") {
                    scanVisibleModelsFolder()
                }

                SecondaryDashboardButton(icon: "square.and.arrow.down", title: "Import") {
                    showingImporter = true
                }

                SecondaryDashboardButton(icon: "slider.horizontal.3", title: "Settings") {
                    showingSettings = true
                }
            }
        }
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
                    Text(defaultModel == nil ? "Set Up Model" : "New Chat")
                        .font(.headline)
                    Text(defaultModel == nil ? "Import or scan a GGUF model first" : "Start with your local model")
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
                EmptyDashboardCard(hasModel: defaultModel != nil)
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
                dashboardStatus = "No .gguf files found in LocalGGUFChat/Models."
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

            dashboardStatus = count == 1 ? "Added 1 model from Models folder." : "Added \(count) models from Models folder."
            errorText = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importModels(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            Task {
                do {
                    var importedItems: [(bookmark: Data, displayName: String, originalPath: String, fileSize: Int64)] = []
                    for url in urls {
                        let displayName = ModelFileAccess.displayName(for: url)
                        let originalPath = url.path
                        let fileSize = ModelFileAccess.fileSize(at: url)
                        let bookmark = try await ModelFileAccess.makeBookmarkAsync(for: url)
                        importedItems.append((bookmark, displayName, originalPath, fileSize))
                    }

                    await MainActor.run {
                        var count = 0
                        do {
                            for item in importedItems {
                                let model = try PersistenceController.shared.upsertModel(
                                    from: item.bookmark,
                                    displayName: item.displayName,
                                    originalPath: item.originalPath,
                                    fileSize: item.fileSize
                                )

                                if generationSettings.defaultModelID.isEmpty, let id = model.id {
                                    generationSettings.defaultModelID = id.uuidString
                                }
                                count += 1
                            }
                            dashboardStatus = count == 1 ? "Imported 1 model." : "Imported \(count) models."
                            errorText = nil
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                } catch {
                    await MainActor.run {
                        errorText = error.localizedDescription
                    }
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct SetupChecklistRow: View {
    let isComplete: Bool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isComplete ? .accentColor : .secondary)
                .font(.headline)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct SecondaryDashboardButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(GlassBackground(cornerRadius: 18))
        }
        .buttonStyle(.plain)
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
    let hasModel: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasModel ? "bubble.left.and.text.bubble.right" : "cpu")
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text(hasModel ? "No chats yet" : "Add a model first")
                .font(.headline)
            Text(hasModel ? "Create your first chat and start talking offline." : "Move a .gguf file into the Models folder, then tap Scan.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(GlassBackground(cornerRadius: 24))
    }
}
