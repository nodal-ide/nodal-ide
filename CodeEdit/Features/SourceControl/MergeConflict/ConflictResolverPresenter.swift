//
//  ConflictResolverPresenter.swift
//  CodeEdit
//
//  Creates/reuses the merge-conflict resolver panel.
//

import AppKit
import SwiftUI

@MainActor
final class ConflictResolverPresenter {
    static let shared = ConflictResolverPresenter()

    private var panel: NSPanel?

    private init() {}

    func show(url: URL, manager: SourceControlManager) {
        AppServices.conflictResolverState.load(url: url, manager: manager)

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Resolve Conflicts"
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 560, height: 400)

        let hostingView = NSHostingView(rootView: ConflictResolverView(state: AppServices.conflictResolverState))
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: 760, height: 600))

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}
