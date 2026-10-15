//
//  BlameViewerPresenter.swift
//  CodeEdit
//
//  Creates/reuses the git blame panel.
//

import AppKit
import SwiftUI

@MainActor
final class BlameViewerPresenter {
    static let shared = BlameViewerPresenter()

    private var panel: NSPanel?

    private init() {}

    /// Loads and shows blame for a file.
    func show(url: URL, manager: SourceControlManager) {
        BlameViewerState.shared.load(url: url, manager: manager)

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Blame"
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 620, height: 420)

        let hostingView = NSHostingView(rootView: BlameViewerView(state: BlameViewerState.shared))
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: 900, height: 560))

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}
