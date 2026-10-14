//
//  ProblemsView.swift
//  CodeEdit
//
//  Native problems list for the Utility Area.
//

import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView

struct ProblemsView: View {
    @ObservedObject private var store = DiagnosticsStore.shared

    var body: some View {
        Group {
            if store.problems.isEmpty {
                Text("No problems")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.problems) { problem in
                    ProblemRow(problem: problem)
                        .contentShape(Rectangle())
                        .onTapGesture { open(problem) }
                }
                .listStyle(.plain)
            }
        }
    }

    private func open(_ problem: EditorProblem) {
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: problem.fileURL,
            display: true
        ) { document, _, _ in
            (document as? CodeFileDocument)?.openOptions = .init(
                cursorPositions: [CursorPosition(range: problem.range)]
            )
        }
    }
}

private struct ProblemRow: View {
    let problem: EditorProblem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(problem.message)
                    .font(.system(size: 12))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch problem.severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    private var color: Color {
        switch problem.severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .hint: return .secondary
        }
    }

    private var subtitle: String {
        let name = problem.fileURL.lastPathComponent
        if let line = problem.line {
            return "\(name):\(line)"
        }
        return name
    }
}