//
//  DebugVariablesView.swift
//  CodeEdit
//
//  The Variables pane: filterable scope outline with lazily-loaded children.
//

import AppKit
import SwiftUI

struct DebugVariablesView: View {
    @ObservedObject var session: DebugSession
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DebugPaneHeader(title: "Variables", systemImage: "cube") {
                DebugSearchField(text: $query)
            }
            Divider()
            content
        }
    }

    private var content: some View {
        Group {
            if session.scopes.isEmpty {
                DebugEmptyState(
                    systemImage: "cube",
                    title: session.state.isStopped ? "No Variables" : "Not Stopped",
                    message: session.state.isStopped
                        ? "No variables in this frame."
                        : "Variables appear here when the program pauses."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.scopes) { scope in
                            ScopeGroupView(session: session, scope: scope, query: query)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// One scope (e.g. "Local", "Superglobals") as an expandable group.
private struct ScopeGroupView: View {
    @ObservedObject var session: DebugSession
    let scope: DAPScope
    let query: String
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VariablesListView(session: session, reference: scope.variablesReference, indent: 1, query: query)
                .padding(.top, 2)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cube")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(scope.name)
                    .font(.system(size: 12, weight: .semibold))
                if let count = session.variablesByReference[scope.variablesReference]?.count {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .task { await session.loadVariables(reference: scope.variablesReference) }
    }
}

/// The variables for a `variablesReference`, loaded lazily and filtered by the search query.
private struct VariablesListView: View {
    @ObservedObject var session: DebugSession
    let reference: Int
    var indent: Int
    let query: String

    var body: some View {
        let variables = (session.variablesByReference[reference] ?? []).filter(matches)
        return Group {
            if variables.isEmpty {
                if query.isEmpty {
                    Text("…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(indent) * 10)
                }
            } else {
                ForEach(Array(variables.enumerated()), id: \.offset) { _, variable in
                    VariableRowView(session: session, variable: variable, indent: indent, query: query)
                }
            }
        }
        .task(id: reference) {
            await session.loadVariables(reference: reference)
        }
    }

    private func matches(_ variable: DAPVariable) -> Bool {
        query.isEmpty
            || variable.name.localizedCaseInsensitiveContains(query)
            || variable.value.localizedCaseInsensitiveContains(query)
    }
}

/// A single variable row, expandable when it has children.
private struct VariableRowView: View {
    @ObservedObject var session: DebugSession
    let variable: DAPVariable
    var indent: Int
    let query: String

    @State private var isExpanded = false
    @State private var hovering = false

    var body: some View {
        Group {
            if variable.variablesReference > 0 {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VariablesListView(
                        session: session,
                        reference: variable.variablesReference,
                        indent: indent + 1,
                        query: query
                    )
                } label: {
                    label
                }
                .onChange(of: isExpanded) { _, expanded in
                    if expanded {
                        Task { await session.loadVariables(reference: variable.variablesReference) }
                    }
                }
            } else {
                label
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .padding(.leading, CGFloat(indent) * 10)
        .background(hovering ? Color.secondary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy Value") { copy(variable.value) }
            Button("Copy Name") { copy(variable.name) }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(variable.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("=")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(variable.value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let type = variable.type, !type.isEmpty {
                Text(type)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private var icon: String {
        switch variable.type?.lowercased() {
        case "int", "integer", "float", "double": return "number"
        case "string": return "textformat"
        case "bool", "boolean": return "switch.2"
        case "array": return "square.stack.3d.up"
        case "object", "stdclass": return "shippingbox"
        default: return variable.variablesReference > 0 ? "circle.grid.2x2" : "circle.dashed"
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// A compact filter field used in debug pane headers.
struct DebugSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 88)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
