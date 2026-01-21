
import SwiftUI

struct TextSelectionModal: View {
    @Environment(\.presentationMode) private var presentationMode
    let text: String

    var body: some View {
        NavigationView {
            SelectableTextView(text: text)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { presentationMode.wrappedValue.dismiss() }
                    }
                }
        }
    }
}
