
import Foundation

struct GenerationConfig: Hashable {
    var maxTokens: Int = 512
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var stopSequences: [String] = []
}

protocol LLMEngine {
    var isLoaded: Bool { get }
    func load(modelURL: URL) async throws
    func unload()
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>
}
