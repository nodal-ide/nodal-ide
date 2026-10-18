//
//  View+isHovering.swift
//  CodeEditModules/StatusBar
//
//  Created by Lukas Pistrol on 22.03.22.
//

import AppKit
import SwiftUI

/// The single way to show a cursor while hovering a view.
///
/// Registers with ``CursorController`` while hovered so the cursor stays correct even when hovered views
/// disappear out of order.
private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var token = UUID()
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hovering ? activate() : deactivate()
            }
            .onDisappear(perform: deactivate)
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        CursorController.shared.push(token, cursor)
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        CursorController.shared.pop(token)
    }
}

extension View {
    /// Shows `cursor` while the view is hovered, restoring the previous cursor on exit and on disappear.
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
