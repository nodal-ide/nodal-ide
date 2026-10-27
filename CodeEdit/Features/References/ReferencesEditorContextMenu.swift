import AppKit
import CodeEditTextView
import CodeEditLang

@MainActor
enum ReferencesEditorContextMenu {
    static let findReferencesTitle = "Find All References"

    /// Returns the "Find All References" context-menu item when a provider that supports
    /// references backs the current file. Otherwise returns nothing, so editors without a
    /// native/LSP reference source don't advertise the action.
    static func items(
        for textView: TextView,
        referenceProvider: (any ReferenceProviding)? = nil
    ) -> [NSMenuItem] {
        let supports = referenceProvider?.supportsReferences == true
        guard supports, let storage = textView.textStorage, storage.length > 0 else { return [] }

        let item = NSMenuItem(
            title: findReferencesTitle,
            action: #selector(CodeEditWindowController.findReferencesFromContextMenu(_:)),
            keyEquivalent: ""
        )
        item.target = nil
        return [item]
    }
}
