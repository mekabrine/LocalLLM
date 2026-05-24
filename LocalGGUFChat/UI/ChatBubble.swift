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
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Group {
                    if isWaitingForAssistantText {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(text)
                            .font(.body)
                            .foregroundColor(isUser ? .white : .primary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isUser ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .overlay(
                    Group {
                        if isOutdated {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.orange.opacity(0.8), lineWidth: 1.5)
                        }
                    }
                )

                if isOutdated {
                    Text("Out of date")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
