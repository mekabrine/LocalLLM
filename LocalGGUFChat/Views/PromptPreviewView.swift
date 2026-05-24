import SwiftUI
import UIKit

struct PromptPreviewView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

    @State private var sampleUserMessage = "hi"
    @State private var selectedProfile: PreviewProfile = .small
    @State private var includeSystemMessage = true

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Test Input"), footer: Text("These previews use the same PromptBuilder path as real generation.")) {
                    TextEditor(text: $sampleUserMessage)
                        .frame(minHeight: 80)
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(PreviewProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    Toggle("Include System Message", isOn: $includeSystemMessage)
                }

                Section(header: Text("Resolved Settings")) {
                    HStack {
                        Text("Small Model Protection")
                        Spacer()
                        Text(generationSettings.smallModelProtection ? "On" : "Off")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Text Model Behavior")
                        Spacer()
                        Text(generationSettings.textModelBehavior.title)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Reasoning")
                        Spacer()
                        Text(generationSettings.reasoningMode.title)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(previews) { preview in
                    Section(header: Text(preview.style.title), footer: footer(for: preview)) {
                        if preview.style == .auto {
                            HStack {
                                Text("Auto resolved to")
                                Spacer()
                                Text(preview.resolvedStyle.title)
                                    .foregroundColor(.secondary)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(preview.prompt.isEmpty ? "<empty prompt>" : preview.prompt)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.18))
                        )

                        Button("Copy Prompt") {
                            UIPasteboard.general.string = preview.prompt
                        }
                    }
                }
            }
            .navigationTitle("Prompt Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Copy All") {
                        UIPasteboard.general.string = allPreviewText
                    }
                }
            }
        }
    }

    private var systemMessage: String {
        includeSystemMessage ? generationSettings.globalSystemMessage : ""
    }

    private var previews: [PromptBuilder.PromptPreview] {
        PromptBuilder.previews(
            sampleUserMessage: sampleUserMessage,
            systemMessage: systemMessage,
            profile: selectedProfile.profile,
            settings: generationSettings
        )
    }

    private var allPreviewText: String {
        previews.map { preview in
            """
            === \(preview.style.title) ===
            Resolved: \(preview.resolvedStyle.title)
            Warnings: \(preview.warnings.joined(separator: "; "))

            \(preview.prompt)
            """
        }.joined(separator: "\n\n")
    }

    private func footer(for preview: PromptBuilder.PromptPreview) -> Text? {
        guard !preview.warnings.isEmpty else { return nil }
        return Text(preview.warnings.joined(separator: "\n"))
    }
}

private enum PreviewProfile: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case veryLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small Model"
        case .medium: return "Medium Model"
        case .large: return "Large Model"
        case .veryLarge: return "Very Large Model"
        }
    }

    var profile: GenerationProfile {
        switch self {
        case .small: return GenerationProfile.profile(forFileSize: 1_120_000_000)
        case .medium: return GenerationProfile.profile(forFileSize: 2_600_000_000)
        case .large: return GenerationProfile.profile(forFileSize: 4_600_000_000)
        case .veryLarge: return GenerationProfile.profile(forFileSize: 8_500_000_000)
        }
    }
}
