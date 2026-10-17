//
//  DebugToolbar.swift
//  CodeEdit
//
//  A floating debug toolbar shown while a debug session is active.
//

import SwiftUI

struct DebugToolbar: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let controller = workspace.debugController {
            DebugToolbarContent(session: controller.session, onStop: controller.stop)
        }
    }
}

private struct DebugToolbarContent: View {
    @ObservedObject var session: DebugSession
    let onStop: () -> Void

    var body: some View {
        if session.state.isActive {
            HStack(spacing: 8) {
                DebugStateBadge(state: session.state)

                Divider().frame(height: 16)

                DebugControls(session: session, onStop: onStop)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
            .shadow(radius: 4, y: 1)
        }
    }
}
