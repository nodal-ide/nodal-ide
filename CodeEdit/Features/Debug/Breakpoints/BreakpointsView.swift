//
//  BreakpointsView.swift
//  CodeEdit
//
//  Lists the workspace's breakpoints (Utility Area "Breakpoints" tab).
//

import SwiftUI
import CodeEditSourceEditor

struct BreakpointsView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let store = workspace.breakpointStore {
            BreakpointsContent(store: store)
        } else {
            Text("No breakpoints")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct BreakpointsContent: View {
    @ObservedObject var store: BreakpointStore

    var body: some View {
        if store.breakpoints.isEmpty {
            Text("No breakpoints")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.breakpoints.sorted { $0.filePath == $1.filePath ? $0.line < $1.line : $0.filePath < $1.filePath })
                { breakpoint in
                    HStack(spacing: 8) {
                        Toggle("", isOn: enabledBinding(breakpoint))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(breakpoint.verified ? Color.red : Color.red.opacity(0.5))
                        Text(breakpoint.fileURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("line \(breakpoint.line)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(breakpoint) }
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            store.remove(breakpoint.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func enabledBinding(_ breakpoint: Breakpoint) -> Binding<Bool> {
        Binding {
            breakpoint.enabled
        } set: { enabled in
            store.setEnabled(breakpoint.id, enabled)
        }
    }

    private func open(_ breakpoint: Breakpoint) {
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: breakpoint.fileURL,
            display: true
        ) { document, _, _ in
            guard let document = document as? CodeFileDocument, let content = document.content?.string else {
                return
            }
            let text = content as NSString
            var currentLine = 1
            var index = 0
            while index < text.length, currentLine < breakpoint.line {
                if text.character(at: index) == 0x0A {
                    currentLine += 1
                }
                index += 1
            }
            document.openOptions = .init(cursorPositions: [CursorPosition(range: NSRange(location: index, length: 0))])
        }
    }
}
