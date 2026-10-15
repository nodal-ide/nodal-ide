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
            DebugEmptyState(
                systemImage: "circle.dashed",
                title: "No Breakpoints",
                message: "Click in the gutter to add a breakpoint."
            )
        } else {
            List {
                ForEach(grouped, id: \.file) { group in
                    Section {
                        ForEach(group.breakpoints) { breakpoint in
                            row(breakpoint, showsFile: false)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            Text(group.file)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text("\(group.breakpoints.count)")
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var grouped: [(file: String, breakpoints: [Breakpoint])] {
        Dictionary(grouping: store.breakpoints, by: \.filePath)
            .map { (file: $0.key, breakpoints: $0.value.sorted { $0.line < $1.line }) }
            .sorted { $0.file < $1.file }
    }

    private func row(_ breakpoint: Breakpoint, showsFile: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding(breakpoint))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(breakpoint.enabled ? "Disable breakpoint" : "Enable breakpoint")
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(breakpoint.verified ? Color.red : Color.red.opacity(0.45))
                .help(breakpoint.verified ? "Verified" : "Unverified")
            if showsFile {
                Text(breakpoint.fileURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("Line \(breakpoint.line)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if let condition = breakpoint.condition, !condition.isEmpty {
                Text(condition)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(breakpoint) }
        .contextMenu {
            Button("Edit Condition…") {
                editCondition(breakpoint)
            }
            Button("Remove", role: .destructive) {
                store.remove(breakpoint.id)
            }
        }
    }

    private func enabledBinding(_ breakpoint: Breakpoint) -> Binding<Bool> {
        Binding {
            breakpoint.enabled
        } set: { enabled in
            store.setEnabled(breakpoint.id, enabled)
        }
    }

    private func editCondition(_ breakpoint: Breakpoint) {
        let alert = NSAlert()
        alert.messageText = "Breakpoint Condition"
        alert.informativeText = "The breakpoint stops only when this expression is true."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = breakpoint.condition ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.setCondition(breakpoint.id, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        case .alertSecondButtonReturn:
            store.setCondition(breakpoint.id, nil)
        default:
            break
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
