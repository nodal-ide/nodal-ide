//
//  BlameViewerView.swift
//  CodeEdit
//
//  Per-line git blame (author/date/commit) for a file.
//

import SwiftUI

struct BlameViewerView: View {
    @ObservedObject var state: BlameViewerState

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.secondary)
            Text(state.fileURL?.lastPathComponent ?? "Blame")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if !state.lines.isEmpty {
                Text("\(state.lines.count) lines")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if state.isLoading, state.lines.isEmpty {
            Spacer()
            ProgressView("Loading blame…").frame(maxWidth: .infinity)
            Spacer()
        } else if let error = state.errorMessage {
            Spacer()
            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer()
        } else if state.lines.isEmpty {
            Spacer()
            Text("No blame available.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.lines) { line in
                        BlameLineRow(line: line, dateFormatter: Self.dateFormatter)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct BlameLineRow: View {
    let line: BlameLine
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(spacing: 8) {
            Text(String(line.lineNumber))
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.commitHash)
                .frame(width: 62, alignment: .leading)
                .foregroundStyle(.blue)
            Text(line.author)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(line.authorDate.map { dateFormatter.string(from: $0) } ?? "")
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(line.summary)
                .frame(width: 190, alignment: .leading)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(line.commitHash) — \(line.author) — \(line.summary)")
    }
}
