import SwiftUI

struct ReferencesNavigatorToolbarBottom: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        ReferencesNavigatorToolbar(session: workspace.referencesSession)
    }
}

@MainActor
private struct ReferencesNavigatorToolbar: View {
    @ObservedObject var session: ReferencesSession

    var body: some View {
        HStack(spacing: 6) {
            Text(summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                session.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh references")
            .accessibilityLabel("Refresh references")
            .disabled(session.target == nil || session.phase.isSearching)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var summary: String {
        switch session.phase {
        case .idle:
            return "No active search"
        case .searching:
            return "Searching…"
        case .results:
            var text = "\(session.totalCount) reference\(session.totalCount == 1 ? "" : "s")"
            if !session.groups.isEmpty {
                text += " in \(session.groups.count) file\(session.groups.count == 1 ? "" : "s")"
            }
            if !session.isComplete {
                text += " · partial"
            }
            return text
        case .failed:
            return "Search failed"
        case .unsupported:
            return "Not available"
        }
    }
}
