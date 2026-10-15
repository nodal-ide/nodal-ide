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
            HStack(spacing: 4) {
                control("play.fill", "Continue") { session.continueExecution() }
                control("pause.fill", "Pause") { session.pause() }

                Divider().frame(height: 14)

                control("arrow.turn.down.right", "Step Over") { session.stepOver() }
                control("arrow.down.right", "Step Into") { session.stepInto() }
                control("arrow.up.right", "Step Out") { session.stepOut() }

                Divider().frame(height: 14)

                control("stop.fill", "Stop") { onStop() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
            .shadow(radius: 4, y: 1)
        }
    }

    private func control(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
