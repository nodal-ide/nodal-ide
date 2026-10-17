//
//  DebugCallStackView.swift
//  CodeEdit
//
//  The Call Stack pane: thread selector + stack frames.
//

import AppKit
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
                        ForEach(Array(session.callStack.enumerated()), id: \.element.id) { index, frame in
                            frameRow(frame, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func frameRow(_ frame: DAPStackFrame, index: Int) -> some View {
        let isSelected = frame.id == session.currentFrameID
        let isHovered = hoveredFrameID == frame.id
        return Button {
            Task { await session.selectFrame(frame) }
        } label: {
            frameLabel(frame, index: index, isSelected: isSelected, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredFrameID = hovering ? frame.id : (hoveredFrameID == frame.id ? nil : hoveredFrameID)
        }
        .contextMenu {
            if let path = frame.source?.path {
                Button("Copy Path") { copy(path) }
            }
            Button("Copy Frame") { copy(frameDescription(frame)) }
        }
    }

    private func frameLabel(
        _ frame: DAPStackFrame,
        index: Int,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if isSelected {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(index)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(frame.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
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
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: isSelected, isHovered: isHovered))
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .opacity(isSelected || isHovered ? 1 : 0.72)
    }

    private func rowBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }

    private func frameDescription(_ frame: DAPStackFrame) -> String {
        if let path = frame.source?.path {
            return "\(frame.name) (\(path):\(frame.line))"
        }
        return frame.name
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
