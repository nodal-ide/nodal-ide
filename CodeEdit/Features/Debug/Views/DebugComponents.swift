//
//  DebugComponents.swift
//  CodeEdit
//
//  Shared building blocks for the debugger panes.
//

import SwiftUI

/// A slim header used at the top of each debug pane.
struct DebugPaneHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: Trailing

    init(title: String, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// A centered empty/placeholder state for a debug pane.
struct DebugEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

/// A small colored chip describing the session state.
struct DebugStateBadge: View {
    let state: DebugSession.State

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private var title: String {
        switch state {
        case .inactive: return "Inactive"
        case .launching: return "Launching"
        case .running: return "Running"
        case .stopped(let reason): return "Paused" + (reason.isEmpty ? "" : " · \(reason)")
        case .terminated: return "Terminated"
        }
    }

    private var color: Color {
        switch state {
        case .inactive, .terminated: return .secondary
        case .launching: return .orange
        case .running: return .green
        case .stopped: return .yellow
        }
    }
}

/// Execution controls (continue/pause/step/stop), shared by the floating toolbar and the Debug header.
struct DebugControls: View {
    @ObservedObject var session: DebugSession
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("play.fill", "Continue", enabled: session.state.isStopped) { session.continueExecution() }
            button("pause.fill", "Pause", enabled: session.state == .running) { session.pause() }

            Divider().frame(height: 14)

            button("arrow.turn.down.right", "Step Over", enabled: session.state.isStopped) { session.stepOver() }
            button("arrow.down.right", "Step Into", enabled: session.state.isStopped) { session.stepInto() }
            button("arrow.up.right", "Step Out", enabled: session.state.isStopped) { session.stepOut() }

            Divider().frame(height: 14)

            button("stop.fill", "Stop") { onStop() }
        }
    }

    private func button(
        _ systemImage: String,
        _ help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
