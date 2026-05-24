import Foundation

enum ModelBackendCompatibility {
    static func blockingIssue(for name: String?) -> String? {
        let lower = (name ?? "").lowercased()
        if lower.contains("gemma-4") || lower.contains("gemma_4") || lower.contains("gemma4") || lower.contains("-e4b-") || lower.contains("e4b-it") {
            return "This Gemma 4 / E4B GGUF appears to need a newer llama.cpp backend than the current SwiftLlama 0.4.0 wrapper. It may work in other apps with newer backends, but LocalLLM cannot load it yet."
        }
        if lower.contains("ud-iq") || lower.contains("iq2_m") || lower.contains("iq1") {
            return "This newer ultra-dense/IQ quantization may not be supported by the current SwiftLlama 0.4.0 backend. Try Q4_K_M, Q4_0, Q5_K_M, Q8_0, or a non-Gemma newer model known to work with this backend."
        }
        return nil
    }

    static func displayStatus(for name: String?) -> String? {
        guard blockingIssue(for: name) != nil else { return nil }
        return "Needs Newer Backend"
    }
}
