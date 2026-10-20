import AppKit
import SwiftUI

/// Status and controls for this project's local site. Observes the workspace coordinator so the
/// indicator follows `.starting`/`.running`/`.needsRestart`/`.error` transitions.
struct LocalDomainStatusCard: View {
    @ObservedObject var coordinator: WorkspaceLocalSiteCoordinator
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let failure = coordinator.state.failure {
                failureView(failure)
            }
            actions
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusTitle)
                .font(.headline)
            Spacer()
            if let url {
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func failureView(_ failure: LocalSiteError) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(failure.localizedDescription, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
            if let suggestion = failure.recoverySuggestion {
                Text(suggestion)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if coordinator.state.isRunning || coordinator.state.failure != nil {
                Button {
                    Task { await coordinator.stopSite() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(coordinator.state.isBusy)
            } else {
                Button {
                    Task { await coordinator.startSite() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }

            Button {
                if let url {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open", systemImage: "safari")
            }
            .disabled(url == nil || !coordinator.state.isRunning)

            Button {
                copyURL()
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            .disabled(url == nil)

            Button {
                revealLogs()
            } label: {
                Label("Reveal Logs", systemImage: "folder")
            }

            Spacer()
        }
        .controlSize(.small)
    }

    private var canStart: Bool {
        url != nil && !coordinator.state.isBusy && !coordinator.state.isRunning
    }

    private var statusTitle: String {
        switch coordinator.state {
        case .idle: return "Stopped"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .needsRestart: return "Needs Restart"
        case .stopping: return "Stopping…"
        case .error: return "Error"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .idle: return .gray
        case .starting, .stopping: return .blue
        case .running: return .green
        case .needsRestart: return .orange
        case .error: return .red
        }
    }

    private func copyURL() {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func revealLogs() {
        let logs = NginxPrefix.default.logsDirectory
        try? FileManager.default.createDirectory(
            at: logs,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        NSWorkspace.shared.activateFileViewerSelecting([logs])
    }
}
