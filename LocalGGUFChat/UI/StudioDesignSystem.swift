import SwiftUI

enum StudioTheme {
    static let background = Color.black
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let surfaceElevated = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let secondaryText = Color(red: 0.63, green: 0.63, blue: 0.67)
    static let border = Color.white.opacity(0.12)
    static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)
}

struct StudioGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var borderColor: Color = StudioTheme.border
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(StudioTheme.surface.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(borderColor, lineWidth: 0.8)
                    )
            )
    }
}

struct StudioIconCircle: View {
    let systemName: String
    var color: Color = .accentColor
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }
}

struct StudioBadge: View {
    let title: String
    var color: Color = .accentColor
    var filled: Bool = true

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundColor(filled ? color : StudioTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(filled ? color.opacity(0.16) : Color.white.opacity(0.08))
            )
    }
}

struct StudioSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(StudioTheme.secondaryText)
            .padding(.horizontal, 4)
    }
}

struct StudioPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StudioSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(StudioTheme.surface.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StudioSettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(StudioTheme.secondaryText)
                }
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 10)
    }
}
