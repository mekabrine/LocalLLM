
import SwiftUI
import CoreData

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appState: AppState

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>

    @State private var showingNewChat = false

    var body: some View {
        NavigationView {
            ZStack {
                List {
                    ForEach(chats) { chat in
                        NavigationLink(destination: ChatView(chat: chat)) {
                            ChatListRow(chat: chat)
                        }
                    }
                    .onDelete(perform: deleteChats)
                }
                .listStyle(.plain)

                if chats.isEmpty {
                    VStack(spacing: 10) {
                        Text("No chats yet").font(.headline)
                        Text("Create a chat and pick a GGUF model.").font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView()
                    .environment(\.managedObjectContext, moc)
                    .environmentObject(appState)
            }
        }
    }

    private func deleteChats(at offsets: IndexSet) {
        offsets.map { chats[$0] }.forEach(moc.delete)
        PersistenceController.shared.save()
    }
}

private struct ChatListRow: View {
    let chat: ChatEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.title ?? "Chat")
                .font(.headline)
                .lineLimit(1)

            Text(lastMessagePreview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                if let model = chat.model?.displayName {
                    Text(model)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(DateFormatters.shortDateTime.string(from: chat.updatedAt ?? chat.createdAt ?? Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var lastMessagePreview: String {
        guard let ordered = chat.messages?.array as? [MessageEntity],
              let last = ordered.last else { return " " }
        return last.text ?? ""
    }
}
