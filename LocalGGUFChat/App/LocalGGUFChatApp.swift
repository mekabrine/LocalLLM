
import SwiftUI

@main
struct LocalGGUFChatApp: App {
    @StateObject private var appState = AppState()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ChatListView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(appState)
        }
    }
}
