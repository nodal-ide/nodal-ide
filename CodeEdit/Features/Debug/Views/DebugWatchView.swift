//
//  DebugWatchView.swift
//  CodeEdit
//
//  The Watch pane: user-defined expressions evaluated against the current frame.
//

import SwiftUI

struct DebugWatchView: View {
    @ObservedObject var session: DebugSession

    @State private var watch: [String] = []
    @State private var results: [String: String] = [:]
    @State private var newExpression = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DebugPaneHeader(title: "Watch", systemImage: "eye") {
                if !watch.isEmpty {
                    Button {
                        watch.removeAll()
                        results.removeAll()
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Clear watch expressions")
                }
            }
            Divider()
            content
            Divider()
            addField
        }
        .onChange(of: session.currentFrameID) { _, _ in refresh() }
        .onChange(of: session.state) { _, _ in refresh() }
    }

    private var content: some View {
        Group {
            if watch.isEmpty {
                DebugEmptyState(
                    systemImage: "eye",
                    title: "No Watch Expressions",
                    message: "Add an expression below to evaluate it when paused."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(watch, id: \.self) { expression in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(expression)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(results[expression] ?? "—")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Button {
                                    watch.removeAll { $0 == expression }
                                    results[expression] = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove expression")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("Add expression", text: $newExpression)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit(add)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func add() {
        let expression = newExpression.trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return }
        newExpression = ""
        if !watch.contains(expression) {
            watch.append(expression)
        }
        refresh()
    }

    private func refresh() {
        guard !watch.isEmpty else { return }
        let frameID = session.currentFrameID
        let expressions = watch
        Task {
            for expression in expressions {
                if let value = await session.evaluate(expression, frameID: frameID) {
                    results[expression] = value
                }
            }
        }
    }
}
