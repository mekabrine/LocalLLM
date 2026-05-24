import Foundation
import SwiftLlama

/// SwiftLlama-backed local GGUF engine.
///
/// The app keeps this behind `LLMEngine` so the UI can stream tokens without
/// knowing about the concrete llama.cpp wrapper. `SwiftLlama` currently exposes
/// prompt streaming through `start(for:)`; sampling controls are stored in
/// `GenerationConfig` and applied where the wrapper exposes them. Stop handling
/// and max-output limiting are enforced around the stream here.
final class SwiftLlamaEngine: LLMEngine {
    private(set) var isLoaded: Bool = false

    private var loadedModelPath: String?
    private var swiftLlama: SwiftLlama?

    func load(modelURL: URL) async throws {
        let path = modelURL.path

        if isLoaded, loadedModelPath == path, swiftLlama != nil {
            return
        }

        swiftLlama = nil
        isLoaded = false

        swiftLlama = try SwiftLlama(modelPath: path)
        loadedModelPath = path
        isLoaded = true
    }

    func unload() async {
        swiftLlama = nil
        loadedModelPath = nil
        isLoaded = false
    }

    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let swiftLlama, isLoaded else {
                continuation.finish(
                    throwing: NSError(
                        domain: "SwiftLlamaEngine",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
                    )
                )
                return
            }

            let task = Task {
                do {
                    var emittedText = ""
                    var approximateTokens = 0

                    for try await token in await swiftLlama.start(for: prompt) {
                        try Task.checkCancellation()

                        let chunk = tokenAfterApplyingStops(
                            token: token,
                            accumulatedText: emittedText,
                            stops: config.stop
                        )

                        if let chunk {
                            if !chunk.isEmpty {
                                emittedText += chunk
                                approximateTokens += Self.approximateTokenCount(in: chunk)
                                continuation.yield(chunk)
                            }
                        } else {
                            continuation.finish()
                            return
                        }

                        if config.maxTokens > 0, approximateTokens >= config.maxTokens {
                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func tokenAfterApplyingStops(token: String, accumulatedText: String, stops: [String]) -> String? {
        guard !stops.isEmpty else { return token }

        let combined = accumulatedText + token
        for stop in stops where !stop.isEmpty {
            if let range = combined.range(of: stop) {
                let previousLength = accumulatedText.count
                let stopStart = combined.distance(from: combined.startIndex, to: range.lowerBound)

                if stopStart <= previousLength {
                    return nil
                }

                let safePrefixLength = stopStart - previousLength
                let safeEnd = token.index(token.startIndex, offsetBy: safePrefixLength)
                return String(token[..<safeEnd])
            }
        }

        return token
    }

    private static func approximateTokenCount(in text: String) -> Int {
        // A small local approximation used only because SwiftLlama's public API
        // does not currently expose max-token generation parameters.
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
