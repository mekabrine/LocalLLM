import SwiftUI

struct ChatInstructionsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var generationSettings: GenerationSettings

    @ObservedObject var chat: ChatEntity
    @State private var draft = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("These instructions only affect this chat. They are combined with the default system message in Settings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Chat Instructions") {
                    TextEditor(text: $draft)
                        .frame(minHeight: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }

                Section("Presets") {
                    Button("Coding Helper") {
                        draft = "Help with coding. Be direct, explain errors clearly, and prefer practical fixes."
                    }
                    Button("Concise Assistant") {
                        draft = "Be concise. Answer directly and avoid extra explanation unless asked."
                    }
                    Button("Study Helper") {
                        draft = "Help me understand topics step by step with simple explanations."
                    }
                    Button("Clear") {
                        draft = ""
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Chat Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        generationSettings.setChatInstructions(draft, for: chat.id)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                draft = generationSettings.chatInstructions(for: chat.id)
            }
        }
    }
}
