//
//  DebugSessionView.swift
//  CodeEdit
//
//  The Debug tab: a resizable multi-pane debugger surface (Call Stack, Variables, Watch, Console).
//

import SwiftUI

struct DebugSessionView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let controller = workspace.debugController {
            DebugSessionContent(session: controller.session, onStop: controller.stop)
        } else {
            DebugEmptyState(
                systemImage: "ladybug",
                title: "No Debug Session",
                message: "Debug a run configuration — or use Run ▸ Debug Current File — to start a session."
            )
        }
    }
}

private struct DebugSessionContent: View {
    @ObservedObject var session: DebugSession
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DebugSessionHeader(session: session, onStop: onStop)
            Divider()
            HSplitView {
                DebugCallStackView(session: session)
                    .frame(minWidth: 180, idealWidth: 240)
                VSplitView {
                    DebugVariablesView(session: session)
                        .frame(minHeight: 120)
                    DebugWatchView(session: session)
                        .frame(minHeight: 120)
                }
                .frame(minWidth: 220, idealWidth: 300)
                DebugConsoleView(session: session)
                    .frame(minWidth: 220, idealWidth: 320)
            }
        }
    }
}

private struct DebugSessionHeader: View {
    @ObservedObject var session: DebugSession
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            DebugStateBadge(state: session.state)
            if session.state.isActive {
                DebugControls(session: session, onStop: onStop)
            }
            Spacer(minLength: 4)
            if let hint = hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.bar)
    }

    private var hint: String? {
        switch session.state {
        case .inactive:
            return nil
        case .launching:
            return "Starting debug adapter…"
        case .running:
            return "Running — use the debug controls to pause or step."
        case .stopped(let reason):
            return reason.isEmpty ? "Paused" : "Paused · \(reason)"
        case .terminated:
            return "Session ended."
        }
    }
}
