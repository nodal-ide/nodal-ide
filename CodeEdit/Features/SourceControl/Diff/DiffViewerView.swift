//
//  DiffViewerView.swift
//  CodeEdit
//
//  Inline, colored rendering of a file's unified diff.
//

import SwiftUI

struct DiffViewerView: View {
    @ObservedObject var state: DiffViewerState

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
            Image(systemName: "arrow.left.arrow.right.square")
                .foregroundStyle(.secondary)
            Text(state.file?.fileURL.lastPathComponent ?? "Diff")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let diff = state.diff {
                Text("+\(diff.additions)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("-\(diff.deletions)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
            }
            Spacer()
            Picker(
                "",
                selection: Binding(get: { state.staged }, set: { state.setStaged($0) })
            ) {
                Text("Working").tag(false)
                Text("Staged").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if state.isLoading, state.diff == nil {
            Spacer()
            ProgressView("Loading diff…").frame(maxWidth: .infinity)
            Spacer()
        } else if let error = state.errorMessage {
            Spacer()
            Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        } else if let diff = state.diff, !diff.hunks.isEmpty {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.hunks) { hunk in
                        hunkHeader(hunk)
                        ForEach(hunk.lines) { line in
                            DiffLineRow(line: line)
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Spacer()
            Text("No changes to show.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button(state.staged ? "Unstage" : "Stage") {
                if state.staged {
                    state.unstageHunk(hunk)
                } else {
                    state.stageHunk(hunk)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12))
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.trailing, 6)

            Text(marker + line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: return Color.green.opacity(0.15)
        case .deletion: return Color.red.opacity(0.15)
        case .context: return .clear
        }
    }
}
