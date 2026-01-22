import Foundation

struct GenerationConfig: Sendable {
    var maxTokens: Int = 256
    var temperature: Double = 0.8
    var topP: Double = 0.95
    var stop: [String] = []
}

/// A minimal local-LLM interface used by the UI.
/// We keep it simple: load a model, stream tokens, unload.
protocol LLMEngine: AnyObject {
    var isLoaded: Bool { get }

    func load(modelURL: URL) async throws
    func unload() async

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>
}
