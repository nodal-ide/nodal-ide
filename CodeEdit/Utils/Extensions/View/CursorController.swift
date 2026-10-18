//
//  CursorController.swift
//  CodeEdit
//

import AppKit

/// Tracks the set of cursors requested by hovered views and shows the top-most one.
///
/// SwiftUI views come and go in an order that does not match `NSCursor.push()`/`pop()` nesting (for example a
/// hovered view can disappear while another nested view is still hovered), which corrupts the global AppKit
/// cursor stack. Instead of relying on that stack, each hovered view registers a token here; the controller
/// always displays the cursor of the most recently registered (top-most) token and restores the previous one
/// when a token is removed.
@MainActor
final class CursorController {
    static let shared = CursorController()

    private var stack: [(token: UUID, cursor: NSCursor)] = []

    private init() {}

    /// Registers `cursor` for `token` (re-registering moves it to the top) and displays it.
    func push(_ token: UUID, _ cursor: NSCursor) {
        stack.removeAll { $0.token == token }
        stack.append((token, cursor))
        cursor.set()
    }

    /// Removes `token` and restores the next cursor down the stack, or the arrow cursor when empty.
    func pop(_ token: UUID) {
        guard let index = stack.firstIndex(where: { $0.token == token }) else { return }
        stack.remove(at: index)
        (stack.last?.cursor ?? .arrow).set()
    }
}
