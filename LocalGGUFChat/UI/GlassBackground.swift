
import SwiftUI

struct GlassBackground: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Placeholder for any future "Liquid Glass" APIs.
                // Uses a heavier material + subtle stroke to approximate a glassy surface.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.20), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }
}
