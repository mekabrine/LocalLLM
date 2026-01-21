
import SwiftUI

struct EditMessageModal: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var message: MessageEntity
    var onSave: () -> Void

    @State private var draft: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SelectableTextView(text: "")
                    .frame(height: 0) // keep UIKit loaded for consistent fonts

                TextEditor(text: $draft)
                    .font(.body)
                    .padding(12)
            }
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        message.text = draft
                        message.editedAt = Date()
                        message.isOutdated = false
                        PersistenceController.shared.save()
                        onSave()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                draft = message.text ?? ""
            }
        }
    }
}
