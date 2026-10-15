//
//  DebugVariablesView.swift
//  CodeEdit
//
//  The Variables pane: scope outline with lazily-loaded children.
//

import SwiftUI

struct DebugVariablesView: View {
    @ObservedObject var session: DebugSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DebugPaneHeader(title: "Variables", systemImage: "cube")
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
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(session.scopes) { scope in
                            DisclosureGroup {
                                ScopeVariablesView(session: session, reference: scope.variablesReference, indent: 1)
                                    .padding(.top, 2)
                            } label: {
                                Text(scope.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// Loads and displays the variables for a `variablesReference`, recursively.
struct ScopeVariablesView: View {
    @ObservedObject var session: DebugSession
    let reference: Int
    var indent: Int

    var body: some View {
        let variables = session.variablesByReference[reference] ?? []
        return Group {
            if variables.isEmpty {
                Text("…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(indent) * 8)
            } else {
                ForEach(variables, id: \.name) { variable in
                    VariableRowView(session: session, variable: variable, indent: indent)
                }
            }
        }
        .task(id: reference) {
            await session.loadVariables(reference: reference)
        }
    }
}

struct VariableRowView: View {
    @ObservedObject var session: DebugSession
    let variable: DAPVariable
    var indent: Int

    @State private var isExpanded = false

    var body: some View {
        if variable.variablesReference > 0 {
            DisclosureGroup(isExpanded: $isExpanded) {
                ScopeVariablesView(session: session, reference: variable.variablesReference, indent: indent + 1)
            } label: {
                label
            }
            .padding(.leading, CGFloat(indent) * 8)
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    Task { await session.loadVariables(reference: variable.variablesReference) }
                }
            }
        } else {
            label.padding(.leading, CGFloat(indent) * 8 + 14)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(variable.name)
                .lineLimit(1)
                .foregroundStyle(.primary)
            Text("=")
                .foregroundStyle(.tertiary)
            Text(variable.value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
