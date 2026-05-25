import Foundation

enum ModelBackendCompatibility {
    static func blockingIssue(for name: String?) -> String? {
        let lower = (name ?? "").lowercased()
        if lower.contains("ud-iq") || lower.contains("iq1") {
            return "This ultra-dense quantization may need the newest llama.cpp support. If it fails, try Q4_K_M, Q4_0, Q5_K_M, or Q8_0."
        }
        return nil
    }

    static func displayStatus(for name: String?) -> String? {
        guard blockingIssue(for: name) != nil else { return nil }
        return "Try Newer Backend"
    }
}
