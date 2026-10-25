import AppKit
import CodeEditSourceEditor
import CodeEditTextView

/// Builds the app-owned items added to the editor's native right-click menu.
///
/// The vendored editor owns Cut/Copy/Paste and exposes `TextView.contextMenuItemsProvider` upward through
/// `TextViewController.onContextMenuItems` and `SourceEditor(onContextMenuItems:)`. Items therefore stay
/// declarative here; activation is routed through the responder chain so this view layer never retains a
/// window controller or an assistant session.
@MainActor
enum AssistantEditorContextMenu {
    static let askAboutSelectionTitle = "Ask Assistant About Selection"

    /// Items appended after the editor's Cut/Copy/Paste group.
    ///
    /// The assistant command intentionally requires a non-empty, in-bounds selection. With no selection the
    /// Editor menu and command palette still attach the active file, so the context menu can stay precise
    /// about what it will do.
    static func items(for textView: TextView) -> [NSMenuItem] {
        guard hasSelection(in: textView) else { return [] }

        let item = NSMenuItem(
            title: askAboutSelectionTitle,
            action: #selector(CodeEditWindowController.askAssistantAboutSelectionFromContextMenu(_:)),
            keyEquivalent: ""
        )
        // A nil target resolves through the responder chain to the window controller that owns the editor.
        item.target = nil
        return [item]
    }

    private static func hasSelection(in textView: TextView) -> Bool {
        guard let textStorage = textView.textStorage,
              let selectionManager = textView.selectionManager
        else { return false }

        return selectionManager.textSelections.contains { selection in
            let range = selection.range
            return range.location != NSNotFound
                && range.length > 0
                && NSMaxRange(range) <= textStorage.length
        }
    }
}
