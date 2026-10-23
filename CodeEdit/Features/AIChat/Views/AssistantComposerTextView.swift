import AppKit
import SwiftUI

struct AssistantComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var isEditable: Bool
    var focusRequest: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        textView.setAccessibilityLabel("Message assistant")
        textView.setAccessibilityRole(.textArea)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastFocusRequest = focusRequest

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            DispatchQueue.main.async {
                context.coordinator.recalculateHeight()
            }
        }

        textView.isEditable = isEditable

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AssistantComposerTextView
        weak var textView: NSTextView?
        var lastFocusRequest = -1

        init(_ parent: AssistantComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            guard !textView.hasMarkedText() else { return false }

            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            guard flags.isEmpty else { return false }

            parent.onSubmit()
            return true
        }

        func recalculateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            layoutManager.ensureLayout(for: textContainer)
            let font = textView.font ?? .systemFont(ofSize: 13)
            let lineHeight = layoutManager.defaultLineHeight(for: font)
            let insets = textView.textContainerInset.height * 2
            let usedHeight = layoutManager.usedRect(for: textContainer).height + insets
            let minimumHeight = lineHeight + insets
            let maximumHeight = lineHeight * 8 + insets
            let newHeight = ceil(min(max(usedHeight, minimumHeight), maximumHeight))

            guard abs(parent.height - newHeight) > 0.5 else { return }
            DispatchQueue.main.async {
                self.parent.height = newHeight
            }
        }
    }
}
