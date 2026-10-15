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
