//
//  BreakpointMenu.swift
//  CodeEdit
//
//  The breakpoint right-click menu in the editor gutter.
//

import AppKit

@MainActor
enum BreakpointMenu {
    /// Builds the context menu for a gutter line (an existing breakpoint gets reveal/enable/delete;
    /// an empty line offers to add one).
    static func menu(for url: URL, line: Int, store: BreakpointStore) -> NSMenu {
        let menu = NSMenu()
        if let breakpoint = store.breakpoint(url, line: line) {
            menu.addItem(ClosureMenuItem(title: "Reveal in Breakpoint Navigator") {
                revealBreakpointNavigator()
            })
            menu.addItem(ClosureMenuItem(title: breakpoint.enabled ? "Disable Breakpoint" : "Enable Breakpoint") {
                store.setEnabled(url, line: line, !breakpoint.enabled)
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "Delete Breakpoint") {
                store.remove(url, line: line)
            })
        } else {
            menu.addItem(ClosureMenuItem(title: "Add Breakpoint") {
                store.add(url, line: line)
            })
        }
        return menu
    }

    private static func revealBreakpointNavigator() {
        (NSApp.keyWindow?.windowController as? CodeEditWindowController)?
            .navigatorSidebarViewModel?
            .setNavigatorTab(tab: .breakpoints)
    }
}

/// An `NSMenuItem` that runs a closure when selected.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func invoke() {
        handler()
    }
}
