import SwiftUI
import UIKit

final class GrowingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let size = sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
}

struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    var minHeight: CGFloat = 40
    var maxHeight: CGFloat = 200
    var isEditable: Bool = true
    var onCommit: (() -> Void)? = nil

    init(
        text: Binding<String>,
        measuredHeight: Binding<CGFloat> = .constant(40),
        minHeight: CGFloat = 40,
        maxHeight: CGFloat = 200,
        isEditable: Bool = true,
        onCommit: (() -> Void)? = nil
    ) {
        _text = text
        _measuredHeight = measuredHeight
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.isEditable = isEditable
        self.onCommit = onCommit
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextEditor
        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            recalculateHeight(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            recalculateHeight(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n", textView.returnKeyType == .send {
                parent.onCommit?()
                return false
            }
            return true
        }

        func recalculateHeight(_ textView: UITextView) {
            let availableWidth = max(textView.bounds.width, 1)
            let fittingSize = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
            let contentHeight = textView.sizeThatFits(fittingSize).height
            let clampedHeight = min(max(contentHeight, parent.minHeight), parent.maxHeight)
            let shouldScroll = contentHeight > parent.maxHeight + 1

            DispatchQueue.main.async {
                if abs(self.parent.measuredHeight - clampedHeight) > 0.5 {
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.parent.measuredHeight = clampedHeight
                    }
                }
                textView.isScrollEnabled = shouldScroll
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = GrowingTextView()
        tv.text = text
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.returnKeyType = onCommit == nil ? .default : .send
        tv.enablesReturnKeyAutomatically = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        DispatchQueue.main.async { context.coordinator.recalculateHeight(tv) }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text { uiView.text = text }
        uiView.isEditable = isEditable
        uiView.returnKeyType = onCommit == nil ? .default : .send
        DispatchQueue.main.async { context.coordinator.recalculateHeight(uiView) }
    }
}
