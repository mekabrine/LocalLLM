import SwiftUI

struct ChatBubble: View {
    let text: String
    let isUser: Bool
    let isOutdated: Bool

    private var isWaitingForAssistantText: Bool {
        !isUser && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOutdated
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 54) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Group {
                    if isWaitingForAssistantText {
                        ThinkingDots()
                            .frame(height: 18)
                    } else {
                        Text(text)
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundColor(isUser ? .white : .primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, isWaitingForAssistantText ? 12 : 11)
                .padding(.horizontal, isWaitingForAssistantText ? 16 : 14)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(borderColor, lineWidth: isOutdated ? 1.5 : 1)
                )

                if isOutdated {
                    Label("Out of date", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            if !isUser { Spacer(minLength: 54) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .transition(.opacity.combined(with: .move(edge: isUser ? .trailing : .leading)))
    }

    private var bubbleBackground: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.white.opacity(0.09))
        }
    }

    private var borderColor: Color {
        if isOutdated { return .orange.opacity(0.85) }
        return isUser ? .white.opacity(0.10) : .white.opacity(0.08)
    }
}

private struct ThinkingDots: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.55)
                    .opacity(animate ? 1.0 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.55)
                        .repeatForever()
                        .delay(Double(index) * 0.16),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
