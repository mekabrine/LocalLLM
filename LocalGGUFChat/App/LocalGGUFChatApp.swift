import SwiftUI

@main
struct LocalGGUFChatApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var generationSettings = GenerationSettings()
    @AppStorage("onboarding.hasCompleted") private var hasCompletedOnboarding = false
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ChatListView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(\.managedObjectContext, persistence.viewContext)
            .environmentObject(appState)
            .environmentObject(generationSettings)
        }
    }
}
