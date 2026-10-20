//
//  SearchPanel.swift
//  CodeEditModules/CodeEditUI
//
//  Created by Pavel Kasila on 20.03.22.
//

import Cocoa

final class SearchPanel: NSPanel, NSWindowDelegate {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 48),
            styleMask: [.fullSizeContentView, .titled, .resizable],
            backing: .buffered, defer: false
        )
        self.delegate = self
        self.center()
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
    }

    override func standardWindowButton(_ button: NSWindow.ButtonType) -> NSButton? {
        let button = super.standardWindowButton(button)
        button?.isHidden = true
        return button
    }

    /// Move focus to the panel's search field whenever the panel becomes key, so the user can type immediately
    /// without clicking. This also covers reopening a cached panel, where SwiftUI's `onAppear` won't fire again.
    override func becomeKey() {
        super.becomeKey()
        DispatchQueue.main.async { [weak self] in
            self?.focusSearchField()
        }
    }

    private func focusSearchField() {
        guard let field = contentView?.firstEditableTextControl() else { return }
        makeFirstResponder(field)
    }

    func windowDidResignKey(_ notification: Notification) {
        if let panel = notification.object as? SearchPanel {
            panel.close()
        }
    }

    func addAsCenteredChild(of parent: NSWindow) {
        parent.addCenteredChildWindow(self, over: parent)
    }
}

private extension NSView {
    /// Finds the first editable text control (an `NSTextField` created by a SwiftUI `TextField`, or a fallback
    /// `NSTextView`) in the view hierarchy.
    func firstEditableTextControl() -> NSResponder? {
        if let textField = self as? NSTextField, textField.isEditable, !textField.isHidden {
            return textField
        }
        if let textView = self as? NSTextView, textView.isEditable, !textView.isHidden {
            return textView
        }
        for subview in subviews {
            if let found = subview.firstEditableTextControl() {
                return found
            }
        }
        return nil
    }
}
