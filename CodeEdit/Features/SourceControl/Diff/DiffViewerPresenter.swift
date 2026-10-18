//
//  DiffViewerPresenter.swift
//  CodeEdit
//
//  Creates/reuses the diff viewer panel. Used by both the Project navigator's "Source Control ▸ Show Diff"
//  and the Source Control navigator's "Show Diff".
//

import AppKit
import SwiftUI

@MainActor
final class DiffViewerPresenter {
    static let shared = DiffViewerPresenter()

    private var panel: NSPanel?

    private init() {}

    /// Loads and shows the diff for a changed file.
    func show(file: GitChangedFile, manager: SourceControlManager) {
        AppServices.diffViewerState.load(file: file, manager: manager)

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Diff"
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 620, height: 420)

        let hostingView = NSHostingView(rootView: DiffViewerView(state: AppServices.diffViewerState))
        hostingView.frame = NSRect(x: 0, y: 0, width: 820, height: 560)
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: 820, height: 560))

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}
