//
//  BreakpointsView.swift
//  CodeEdit
//
//  The Breakpoints navigator: breakpoints grouped by file, with the source line shown.
//

import AppKit
import SwiftUI

struct BreakpointsView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let store = workspace.breakpointStore {
            BreakpointsContent(store: store)
        } else {
            DebugEmptyState(
                systemImage: "circle.dashed",
                title: "No Breakpoints",
                message: "Open a folder to manage breakpoints."
            )
        }
    }
}

private struct BreakpointGroup: Identifiable {
    let path: String
    let breakpoints: [Breakpoint]
    var id: String { path }
}

private struct BreakpointsContent: View {
    @ObservedObject var store: BreakpointStore
    @State private var query = ""
    @State private var fileLines: [String: [String]] = [:]

    var body: some View {
        Group {
            if store.breakpoints.isEmpty {
                DebugEmptyState(
                    systemImage: "circle.dashed",
                    title: "No Breakpoints",
                    message: "Click in the editor gutter to add a breakpoint."
                )
            } else {
                VStack(spacing: 0) {
                    DebugSearchField(text: $query)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    Divider()
                    if groups.isEmpty {
                        DebugEmptyState(systemImage: "magnifyingglass", title: "No Matches", message: nil)
                    } else {
                        list
                    }
                }
            }
        }
        .onAppear(perform: loadLines)
        .onChange(of: store.breakpoints) { _, _ in loadLines() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(groups) { group in
                    BreakpointFileGroupView(
                        store: store,
                        path: group.path,
                        breakpoints: group.breakpoints,
                        lineText: lineText
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var groups: [BreakpointGroup] {
        let grouped = Dictionary(grouping: store.breakpoints, by: \.filePath)
        return grouped.keys.sorted().compactMap { path in
            let items = (grouped[path] ?? []).sorted { $0.line < $1.line }
            guard !query.isEmpty else { return BreakpointGroup(path: path, breakpoints: items) }
            let needle = query.lowercased()
            if URL(filePath: path).lastPathComponent.lowercased().contains(needle) {
                return BreakpointGroup(path: path, breakpoints: items)
            }
            let matched = items.filter { matches($0, needle) }
            return matched.isEmpty ? nil : BreakpointGroup(path: path, breakpoints: matched)
        }
    }

    private func matches(_ breakpoint: Breakpoint, _ needle: String) -> Bool {
        if "\(breakpoint.line)".contains(needle) { return true }
        if let condition = breakpoint.condition?.lowercased(), condition.contains(needle) { return true }
        if let text = lineText(breakpoint)?.lowercased(), text.contains(needle) { return true }
        return false
    }

    private func lineText(_ breakpoint: Breakpoint) -> String? {
        guard let lines = fileLines[breakpoint.filePath],
              breakpoint.line >= 1, breakpoint.line <= lines.count else { return nil }
        let text = lines[breakpoint.line - 1].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private func loadLines() {
        for path in Set(store.breakpoints.map(\.filePath)) where fileLines[path] == nil {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                fileLines[path] = content.components(separatedBy: .newlines)
            }
        }
    }
}

private struct BreakpointFileGroupView: View {
    @ObservedObject var store: BreakpointStore
    let path: String
    let breakpoints: [Breakpoint]
    let lineText: (Breakpoint) -> String?

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(breakpoints) { breakpoint in
                BreakpointRowView(store: store, breakpoint: breakpoint, lineText: lineText(breakpoint))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(URL(filePath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(breakpoints.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .help(path)
        }
        .padding(.horizontal, 8)
    }
}

private struct BreakpointRowView: View {
    @ObservedObject var store: BreakpointStore
    let breakpoint: Breakpoint
    let lineText: String?

    @EnvironmentObject private var workspace: WorkspaceDocument
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                store.setEnabled(breakpoint.id, !breakpoint.enabled)
            } label: {
                Image(systemName: breakpoint.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(breakpoint.enabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(breakpoint.enabled ? "Disable breakpoint" : "Enable breakpoint")

            Text("\(breakpoint.line)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)

            Text(lineText ?? "Line \(breakpoint.line)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineText == nil ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if breakpoint.condition != nil {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .help("Condition: \(breakpoint.condition ?? "")")
            }
            if !breakpoint.verified {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help("Unverified by the debug adapter")
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .background(hovering ? Color.secondary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { workspace.revealSourceLocation(url: breakpoint.fileURL, line: breakpoint.line) }
        .contextMenu {
            Button("Reveal in Editor") {
                workspace.revealSourceLocation(url: breakpoint.fileURL, line: breakpoint.line)
            }
            Button("Edit Condition…") { BreakpointActions.editCondition(store: store, breakpoint: breakpoint) }
            Button(breakpoint.enabled ? "Disable" : "Enable") {
                store.setEnabled(breakpoint.id, !breakpoint.enabled)
            }
            Divider()
            Button("Remove", role: .destructive) { store.remove(breakpoint.id) }
        }
    }
}

@MainActor
enum BreakpointActions {
    /// Prompts for a breakpoint condition and stores it.
    static func editCondition(store: BreakpointStore, breakpoint: Breakpoint) {
        let alert = NSAlert()
        alert.messageText = "Edit Breakpoint Condition"
        alert.informativeText = "Leave empty to break unconditionally."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = breakpoint.condition ?? ""
        field.placeholderString = "e.g. $x > 10"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.setCondition(breakpoint.id, field.stringValue)
        }
    }
}

// MARK: - Navigator bottom bar

struct BreakpointsNavigatorToolbarBottom: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let store = workspace.breakpointStore {
            BreakpointsBottomBar(store: store)
        }
    }
}

private struct BreakpointsBottomBar: View {
    @ObservedObject var store: BreakpointStore

    var body: some View {
        HStack(spacing: 6) {
            Text(store.breakpoints.isEmpty ? "No Breakpoints" : "\(store.breakpoints.count) Breakpoints")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                store.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(store.breakpoints.isEmpty)
            .help("Remove all breakpoints")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
