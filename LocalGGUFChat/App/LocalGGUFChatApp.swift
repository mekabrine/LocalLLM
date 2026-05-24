import SwiftUI

@main
struct LocalGGUFChatApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var generationSettings = GenerationSettings()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ChatListView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(appState)
                .environmentObject(generationSettings)
        }
    }
}
