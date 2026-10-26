import AppKit
import CodeEditTextView

@MainActor
enum ReferencesEditorContextMenu {
    static let findReferencesTitle = "Find All References"

    static func items(for textView: TextView) -> [NSMenuItem] {
        guard let storage = textView.textStorage, storage.length > 0 else { return [] }

        let item = NSMenuItem(
            title: findReferencesTitle,
            action: #selector(CodeEditWindowController.findReferencesFromContextMenu(_:)),
            keyEquivalent: ""
        )
        item.target = nil
        return [item]
    }
}
