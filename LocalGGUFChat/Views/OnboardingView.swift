import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.accentColor)
                        .frame(width: 92, height: 92)
                        .background(Circle().fill(Color.white.opacity(0.08)))

                    Text("LocalLLM")
                        .font(.largeTitle.weight(.bold))

                    Text("Private AI on your iPhone")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 14) {
                    OnboardingFeature(icon: "lock.shield.fill", title: "Runs on-device", subtitle: "Chats and models stay local.")
                    OnboardingFeature(icon: "doc.fill", title: "Use GGUF models", subtitle: "Place large files in Files, then scan the Models folder.")
                    OnboardingFeature(icon: "bubble.left.and.bubble.right.fill", title: "Start chatting", subtitle: "Pick a model, create a chat, and generate offline.")
                }

                Spacer()

                Button {
                    onFinish()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct OnboardingFeature: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(GlassBackground(cornerRadius: 20))
    }
}
