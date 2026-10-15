//
//  DebugCallStackView.swift
//  CodeEdit
//
//  The Call Stack pane: thread selector + stack frames.
//

import SwiftUI

struct DebugCallStackView: View {
    @ObservedObject var session: DebugSession
    @State private var hoveredFrameID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DebugPaneHeader(title: "Call Stack", systemImage: "list.bullet.indent") {
                if session.threads.count > 1 {
                    threadMenu
                }
            }
            Divider()
            content
        }
    }

    private var threadMenu: some View {
        Menu {
            ForEach(session.threads) { thread in
                Button(thread.name) {
                    Task { await session.selectThread(thread.id) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text(session.threads.first { $0.id == session.currentThreadID }?.name ?? "Thread")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var content: some View {
        Group {
            if session.callStack.isEmpty {
                DebugEmptyState(
                    systemImage: "pause.circle",
                    title: session.state.isStopped ? "No Frames" : "Not Stopped",
                    message: session.state.isStopped
                        ? "The call stack is empty."
                        : "Paused programs show their call stack here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.callStack) { frame in
                            frameRow(frame)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func frameRow(_ frame: DAPStackFrame) -> some View {
        let isSelected = frame.id == session.currentFrameID
        return Button {
            Task { await session.selectFrame(frame) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(frame.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let source = frame.source?.name {
                        Text("\(source):\(frame.line)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected, frame: frame))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredFrameID = $0 ? frame.id : (hoveredFrameID == frame.id ? nil : hoveredFrameID) }
    }

    private func rowBackground(isSelected: Bool, frame: DAPStackFrame) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if hoveredFrameID == frame.id {
            return Color.secondary.opacity(0.08)
        }
        return .clear
    }
}
