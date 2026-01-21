
import SwiftUI
import UIKit

struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 40
    var maxHeight: CGFloat = 140
    var isEditable: Bool = true
    var onCommit: (() -> Void)? = nil

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextEditor
        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            UIView.performWithoutAnimation {
                textView.invalidateIntrinsicContentSize()
                textView.superview?.layoutIfNeeded()
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n", (textView.returnKeyType == .send || textView.returnKeyType == .done) {
                parent.onCommit?()
                return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.text = text
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.returnKeyType = .default
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.isEditable = isEditable
    }
}

extension UITextView {
    open override var intrinsicContentSize: CGSize {
        let size = sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
}
