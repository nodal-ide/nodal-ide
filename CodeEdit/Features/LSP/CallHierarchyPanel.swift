//
//  CallHierarchyPanel.swift
//  CodeEdit
//

import AppKit

/// A persistent panel that hosts the call-hierarchy tree. Unlike the search panels it does not close when it
/// loses key focus, so the user can expand nodes and jump between call sites.
final class CallHierarchyPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.title = "Call Hierarchy"
        self.isReleasedWhenClosed = false
    }
}
