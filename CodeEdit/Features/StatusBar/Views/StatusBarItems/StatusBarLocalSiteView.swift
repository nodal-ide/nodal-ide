import SwiftUI
import AppKit

/// Status-bar indicator for the workspace's local site. Shows the live state, and offers the same
/// quick actions users need after a run: open, copy the URL, or reveal the generated logs.
struct StatusBarLocalSiteView: View {
    @ObservedObject var coordinator: WorkspaceLocalSiteCoordinator
    @ObservedObject var settingsManager: CEWorkspaceSettings

    @AppSettings(\.localDomains.portMode)
    private var portMode

    private var site: LocalSiteSettings {
        settingsManager.settings.site
    }

    private var domain: SiteDomain? {
        try? SiteDomain(site.domain)
    }

    private var siteURL: URL? {
        guard let domain else { return nil }
        return LocalSiteAddress.url(domain: domain, https: site.https, portMode: portMode)
    }

    private var logsDirectory: URL {
        NginxPrefix.default.logsDirectory
    }

    var body: some View {
        if site.enabled || coordinator.state != .idle {
            Menu {
                Button("Open Site") {
                    if let siteURL {
                        NSWorkspace.shared.open(siteURL)
                    }
                }
                .disabled(siteURL == nil)

                Button("Copy URL") {
                    if let siteURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(siteURL.absoluteString, forType: .string)
                    }
                }
                .disabled(siteURL == nil)

                Button("Reveal Logs") {
                    NSWorkspace.shared.activateFileViewerSelecting([logsDirectory])
                }

                Divider()

                if coordinator.state.isRunning {
                    Button("Stop Site") {
                        Task { await coordinator.stopSite() }
                    }
                } else {
                    Button("Start Site") {
                        Task { await coordinator.startSite() }
                    }
                    .disabled(coordinator.state.isBusy)
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 6, height: 6)
                    Text(domain?.value ?? "Local Site")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(helpText)
            .onChange(of: coordinator.state) { _, state in
                postNotification(for: state)
            }
        }
    }

    private var indicatorColor: Color {
        switch coordinator.state {
        case .running, .needsRestart:
            return .green
        case .starting, .stopping:
            return .orange
        case .error:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var helpText: String {
        if let failure = coordinator.state.failure {
            return failure.errorDescription ?? "Local site failed."
        }
        if let siteURL {
            return siteURL.absoluteString
        }
        return "Local Site"
    }

    private func postNotification(for state: LocalSiteState) {
        let id = "local-site-\(domain?.value ?? coordinator.workspaceURL.path(percentEncoded: false))"
        switch state {
        case .running:
            TaskNotificationHandler.postTask(
                toWorkspace: coordinator.workspaceURL,
                action: .create,
                model: TaskNotificationModel(
                    id: id,
                    title: "Site running",
                    message: siteURL?.absoluteString
                )
            )
            TaskNotificationHandler.postTask(
                toWorkspace: coordinator.workspaceURL,
                action: .deleteWithDelay,
                model: TaskNotificationModel(id: id, title: ""),
                delay: 6
            )
        case .error(let failure):
            var message = failure.errorDescription ?? "The local site could not be started."
            if let suggestion = failure.recoverySuggestion {
                message += " \(suggestion)"
            }
            TaskNotificationHandler.postTask(
                toWorkspace: coordinator.workspaceURL,
                action: .createWithPriority,
                model: TaskNotificationModel(
                    id: id,
                    title: "Couldn't start site",
                    message: message
                )
            )
            TaskNotificationHandler.postTask(
                toWorkspace: coordinator.workspaceURL,
                action: .deleteWithDelay,
                model: TaskNotificationModel(id: id, title: ""),
                delay: 10
            )
        default:
            break
        }
    }
}
