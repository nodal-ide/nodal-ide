//
//  DebugSessionView.swift
//  CodeEdit
//
//  Debug panes: Call Stack, Variables, Watch, and the Debug Console.
//

import SwiftUI

struct DebugSessionView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let controller = workspace.debugController {
            DebugSessionContent(session: controller.session)
        } else {
            Text("No debug session")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DebugSessionContent: View {
    @ObservedObject var session: DebugSession

    @State private var watch: [String] = []
    @State private var watchResults: [String: String] = [:]
    @State private var newWatch = ""
    @State private var consoleInput = ""

    var body: some View {
        HSplitView {
            leftColumn.frame(minWidth: 240)
            consoleColumn.frame(minWidth: 260)
        }
        .onChange(of: session.currentFrameID) { _, _ in refreshWatch() }
        .onChange(of: session.state) { _, _ in refreshWatch() }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Call Stack") { callStack }
                section("Variables") { variables }
                section("Watch") { watchList }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder private var callStack: some View {
        if session.threads.count > 1 {
            Menu {
                ForEach(session.threads) { thread in
                    Button(thread.name) {
                        Task { await session.selectThread(thread.id) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                    Text(session.threads.first { $0.id == session.currentThreadID }?.name ?? "Thread")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }
                .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        if session.callStack.isEmpty {
            Text("Not stopped").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            ForEach(session.callStack) { frame in
                Button {
                    Task { await session.selectFrame(frame) }
                } label: {
                    HStack(spacing: 6) {
                        Text(frame.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("\(frame.source?.name ?? ""):\(frame.line)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(frame.id == session.currentFrameID ? Color.accentColor.opacity(0.2) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var variables: some View {
        if session.scopes.isEmpty {
            Text(session.state.isStopped ? "No variables" : "Not stopped")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            ForEach(session.scopes) { scope in
                DisclosureGroup {
                    ScopeVariablesView(session: session, reference: scope.variablesReference, indent: 1)
                } label: {
                    Text(scope.name).font(.system(size: 12))
                }
            }
        }
    }

    @ViewBuilder private var watchList: some View {
        ForEach(watch, id: \.self) { expression in
            HStack(alignment: .top, spacing: 6) {
                Text(expression).font(.system(size: 11, design: .monospaced))
                Spacer(minLength: 4)
                Text(watchResults[expression] ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button {
                    watch.removeAll { $0 == expression }
                    watchResults[expression] = nil
                    refreshWatch()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        HStack(spacing: 4) {
            Image(systemName: "plus")
            TextField("Add expression", text: $newWatch)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit {
                    let expression = newWatch.trimmingCharacters(in: .whitespaces)
                    guard !expression.isEmpty else { return }
                    newWatch = ""
                    if !watch.contains(expression) { watch.append(expression) }
                    refreshWatch()
                }
        }
    }

    private func refreshWatch() {
        guard !watch.isEmpty else { return }
        let frameID = session.currentFrameID
        let expressions = watch
        Task {
            for expression in expressions {
                if let result = await session.evaluate(expression, frameID: frameID) {
                    watchResults[expression] = result
                }
            }
        }
    }

    // MARK: - Console

    private var consoleColumn: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(session.console.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: session.console.count) { _, _ in
                    guard !session.console.isEmpty else { return }
                    withAnimation { proxy.scrollTo(session.console.count - 1, anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.system(size: 10))
                TextField("Evaluate expression", text: $consoleInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(evaluateInput)
            }
            .padding(8)
        }
    }

    private func evaluateInput() {
        let expression = consoleInput.trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return }
        consoleInput = ""
        session.log("> \(expression)")
        Task {
            if let result = await session.evaluate(expression, frameID: session.currentFrameID) {
                session.log(result)
            } else {
                session.log("<unavailable>")
            }
        }
    }
}

/// Loads and displays the variables for a `variablesReference`, recursively.
private struct ScopeVariablesView: View {
    @ObservedObject var session: DebugSession
    let reference: Int
    var indent: Int

    var body: some View {
        let variables = session.variablesByReference[reference] ?? []
        return Group {
            if variables.isEmpty {
                Text("…").foregroundStyle(.secondary).font(.system(size: 11))
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

private struct VariableRowView: View {
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
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    Task { await session.loadVariables(reference: variable.variablesReference) }
                }
            }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(variable.name).lineLimit(1)
            Spacer(minLength: 4)
            Text(variable.value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.leading, CGFloat(indent) * 2)
    }
}
