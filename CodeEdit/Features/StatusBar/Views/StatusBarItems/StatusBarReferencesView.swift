import AppKit
import SwiftUI

struct StatusBarReferencesView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        ReferencesStatusPill(session: workspace.referencesSession)
    }
}

@MainActor
private struct ReferencesStatusPill: View {
    @ObservedObject var session: ReferencesSession

    var body: some View {
        if session.target != nil, isVisible {
            Button {
                (NSApp.keyWindow?.windowController as? CodeEditWindowController)?.showReferencesNavigator()
            } label: {
                HStack(spacing: 4) {
                    if session.phase.isSearching {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 9))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .help("Show references")
            .accessibilityLabel("Show references")
        }
    }

    private var isVisible: Bool {
        switch session.phase {
        case .idle, .unsupported:
            return false
        case .searching, .results, .failed:
            return true
        }
    }

    private var label: String {
        switch session.phase {
        case .searching:
            return "References…"
        case .results:
            return "\(session.totalCount) reference\(session.totalCount == 1 ? "" : "s")"
        case .failed:
            return "References failed"
        default:
            return "References"
        }
    }

    private var icon: String {
        if case .failed = session.phase {
            return "exclamationmark.triangle"
        }
        return "arrow.turn.up.right"
    }
}
