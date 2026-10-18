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
/// Balances `NSCursor.push()`/`pop()` so a view that disappears while hovered still pops exactly once.
private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hovering ? push() : pop()
            }
            .onDisappear(perform: pop)
    }

    private func push() {
        guard !isPushed else { return }
        isPushed = true
        cursor.push()
    }

    private func pop() {
        guard isPushed else { return }
        isPushed = false
        NSCursor.pop()
    }
}

extension View {
    /// Shows `cursor` while the view is hovered, popping it on exit and on disappear (balanced).
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
