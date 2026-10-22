import SwiftUI

struct ExtensionUpdatesView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @EnvironmentObject private var installation: ExtensionInstallationViewModel
    @EnvironmentObject private var languageManager: LanguageExtensionManager

    var onShowDiscover: () -> Void = {}
    var onShowSources: () -> Void = {}

    private var index: ExtensionUpdateIndex {
        ExtensionUpdateIndex(
            installed: languageManager.extensions,
            catalogs: marketplace.catalogs,
            sources: marketplace.sources,
            appVersion: Bundle.versionString
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = marketplace.sourceHealth.notice {
                SourceStatusBanner(
                    title: notice.title,
                    detail: notice.detail,
                    onRefresh: { Task { await marketplace.refreshAll() } },
                    onShowSources: onShowSources,
                    canRefresh: marketplace.hasRefreshableSources && !marketplace.isRefreshing
                )
                Divider()
            }

            content
        }
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await marketplace.refreshAll() }
                } label: {
                    if marketplace.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh Catalogs", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(marketplace.isRefreshing || !marketplace.hasRefreshableSources)
                .accessibilityLabel("Refresh extension catalogs")
                .help("Refresh trusted, enabled sources")
            }
        }
        .task { await marketplace.loadCachedCatalogs() }
    }

    @ViewBuilder private var content: some View {
        if index.trackedCount == 0 {
            ExtensionEmptyState(
                systemImage: "arrow.down.circle",
                title: "No Marketplace Extensions",
                message: "Install an extension from Discover to check for updates from its source.",
                primaryAction: .init("Browse Discover", systemImage: "square.grid.2x2") {
                    onShowDiscover()
                }
            )
        } else if index.availableUpdates.isEmpty, index.issues.isEmpty {
            ExtensionEmptyState(
                systemImage: "checkmark.circle",
                title: "Everything Is Up to Date",
                message: upToDateMessage,
                primaryAction: .init("Refresh Catalogs", systemImage: "arrow.clockwise") {
                    Task { await marketplace.refreshAll() }
                },
                secondaryAction: .init("Browse Discover", systemImage: "square.grid.2x2") {
                    onShowDiscover()
                }
            )
        } else {
            List {
                if !index.availableUpdates.isEmpty {
                    Section("Available Updates") {
                        ForEach(index.availableUpdates) { update in
                            ExtensionUpdateRow(
                                update: update,
                                isCached: marketplace.isShowingCachedData(for: update.source.id)
                            )
                        }
                    }
                }

                if !index.issues.isEmpty {
                    Section("Needs Attention") {
                        ForEach(index.issues) { issue in
                            ExtensionUpdateIssueRow(
                                issue: issue,
                                onShowDiscover: onShowDiscover,
                                onShowSources: onShowSources,
                                onRefresh: { Task { await marketplace.refreshAll() } }
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var upToDateMessage: String {
        let count = index.upToDate.count
        let noun = count == 1 ? "extension is" : "extensions are"
        return "\(count) marketplace \(noun) up to date for the recorded source."
    }
}

private struct ExtensionUpdateRow: View {
    @EnvironmentObject private var installation: ExtensionInstallationViewModel
    let update: ExtensionUpdate
    let isCached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.installed.name)
                        .font(.headline)
                    Text("\(update.installedVersion) → \(update.availableVersion)")
                        .font(.callout.monospaced())
                    HStack(spacing: 6) {
                        Text(update.source.name)
                        if isCached {
                            Text("·")
                            Label("Cached", systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                action
            }

            if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(update.installed.name), update from \(update.installedVersion) " +
                "to \(update.availableVersion), source \(update.source.name)"
        )
    }

    private var state: ExtensionInstallationState {
        installation.state(for: update.candidate.id)
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .preparing, .downloading, .extracting, .validating, .installing, .cancelling:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("Cancel", role: .cancel) {
                    installation.cancel(update.candidate.id)
                }
                .disabled(state == .cancelling)
            }
        case .succeeded:
            Label("Updated", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Button("Retry") { install() }
        case .cancelled:
            Button("Update") { install() }
        case .idle:
            Button("Update \(update.availableVersion)") { install() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func install() {
        installation.install(update.candidate, from: update.source)
    }
}

private struct ExtensionUpdateIssueRow: View {
    let issue: ExtensionUpdateIssue
    let onShowDiscover: () -> Void
    let onShowSources: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.installed.name)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Source: \(issue.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        let installedVersion = issue.installed.version ?? "an unknown version"
        switch issue.reason {
        case .sourceMissing:
            return "\(installedVersion) is still installed. Its source was removed, so update " +
                "checks are unavailable until the source returns."
        case .sourceDisabled:
            return "\(installedVersion) is still installed. Enable the source to check for updates."
        case .sourceUntrusted:
            return "\(installedVersion) is still installed. Trust the source to check for updates."
        case .catalogUnavailable:
            return "No cached catalog is available for this source. Refresh to check for updates."
        case .notInCatalog:
            return "\(installedVersion) is still installed, but this source no longer lists it. " +
                "Choose another source in Discover to switch explicitly."
        case .incompatible(let requirement):
            return "The latest version requires Nodal \(requirement). This app is " +
                "\(Bundle.versionString ?? "an unknown version"), so the update is not offered."
        case .invalidRequirement(let requirement):
            return "The source declares an unsupported compatibility requirement " +
                "(\(requirement)), so the update is not offered."
        case .invalidVersion(let version):
            return "The installed or available version (\(version)) could not be compared."
        case .unknownHostVersion:
            return "The app version is unavailable, so package compatibility cannot be verified."
        }
    }

    @ViewBuilder private var action: some View {
        switch issue.reason {
        case .catalogUnavailable:
            Button("Refresh", action: onRefresh)
        case .notInCatalog:
            Button("Discover", action: onShowDiscover)
        case .sourceMissing, .sourceDisabled, .sourceUntrusted:
            Button("Manage Sources", action: onShowSources)
        case .incompatible, .invalidRequirement, .invalidVersion, .unknownHostVersion:
            Button("Discover", action: onShowDiscover)
        }
    }
}
