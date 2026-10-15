//
//  ConflictResolverView.swift
//  CodeEdit
//
//  Merge-conflict resolution UI.
//

import SwiftUI

struct ConflictResolverView: View {
    @ObservedObject var state: ConflictResolverState

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
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text(state.fileURL?.lastPathComponent ?? "Resolve Conflicts")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if state.conflicts.isEmpty, state.fileURL != nil {
                Text("All conflicts resolved")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else if !state.conflicts.isEmpty {
                Text("\(state.conflicts.count) conflict\(state.conflicts.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            Spacer()
            if state.markedResolved {
                Label("Marked as resolved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                Button("Mark as Resolved") {
                    state.markResolved()
                }
                .disabled(!state.conflicts.isEmpty || state.fileURL == nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if state.isLoading {
            Spacer()
            ProgressView("Loading…").frame(maxWidth: .infinity)
            Spacer()
        } else if let error = state.errorMessage {
            Spacer()
            Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        } else if state.conflicts.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("No conflicts in this file.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.conflicts) { conflict in
                        ConflictCardView(conflict: conflict) { resolution in
                            state.resolve(conflict, as: resolution)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ConflictCardView: View {
    let conflict: ConflictBlock
    let onResolve: (ConflictResolution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }

            pane(title: "Ours — \(conflict.oursLabel)", text: conflict.ours, color: .green)
            pane(title: "Theirs — \(conflict.theirsLabel)", text: conflict.theirs, color: .blue)
            if let base = conflict.base {
                pane(title: "Base", text: base, color: .gray)
            }

            HStack(spacing: 8) {
                Button("Accept Ours") { onResolve(.ours) }
                Button("Accept Theirs") { onResolve(.theirs) }
                Button("Keep Both") { onResolve(.both(oursFirst: true)) }
                Spacer()
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.35))
        )
    }

    private func pane(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(6)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
