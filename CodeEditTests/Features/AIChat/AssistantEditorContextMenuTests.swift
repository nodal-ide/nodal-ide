@testable import CodeEdit
import AppKit
import CodeEditTextView
import Testing

@MainActor
@Suite
struct AssistantEditorContextMenuTests {
    @Test
    func includesAskItemForAValidSelection() {
        let textView = TextView(string: "let value = 2")
        textView.selectionManager.setSelectedRange(NSRange(location: 4, length: 5))

        let items = AssistantEditorContextMenu.items(for: textView)

        #expect(items.count == 1)
        let item = items.first
        #expect(item?.title == "Ask Assistant About Selection")
        #expect(
            item?.action
                == #selector(CodeEditWindowController.askAssistantAboutSelectionFromContextMenu(_:))
        )
        #expect(item?.target == nil)
    }

    @Test
    func omitsAskItemWithoutANonEmptySelection() {
        let textView = TextView(string: "abc")
        textView.selectionManager.setSelectedRange(NSRange(location: 1, length: 0))

        #expect(AssistantEditorContextMenu.items(for: textView).isEmpty)
    }

    @Test
    func omitsAskItemForAnOutOfBoundsSelection() {
        let textView = TextView(string: "abc")
        textView.selectionManager.setSelectedRange(NSRange(location: 2, length: 10))

        #expect(AssistantEditorContextMenu.items(for: textView).isEmpty)
    }
}
