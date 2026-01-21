
import Foundation

@MainActor
final class AppState: ObservableObject {
    // Cache loaded engines by model id so switching chats is fast.
    private var engines: [UUID: SwiftLlamaEngine] = [:]

    func engine(for modelId: UUID) -> SwiftLlamaEngine {
        if let e = engines[modelId] { return e }
        let e = SwiftLlamaEngine()
        engines[modelId] = e
        return e
    }

    func unloadAllModels() {
        for (_, engine) in engines {
            Task { await engine.unload() }
        }
        engines.removeAll()
    }
}
