//
//  DebugConsoleView.swift
//  CodeEdit
//
//  The integrated Debug Console: adapter output + expression evaluation.
//

import AppKit
import SwiftUI

struct DebugConsoleView: View {
    @ObservedObject var session: DebugSession

    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DebugPaneHeader(title: "Debug Console", systemImage: "terminal") {
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.console.joined(separator: "\n"), forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.console.isEmpty)
                    .help("Copy console")

                    Button {
                        session.clearConsole()
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.console.isEmpty)
                    .help("Clear console")
                }
            }
            Divider()
            console
            Divider()
            inputBar
        }
    }

    private var console: some View {
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
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("Evaluate expression", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(evaluate)
        }
        .padding(8)
    }

    private func evaluate() {
        let expression = input.trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return }
        input = ""
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
