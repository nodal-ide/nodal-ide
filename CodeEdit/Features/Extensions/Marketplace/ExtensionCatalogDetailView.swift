//
//  ExtensionCatalogDetailView.swift
//  CodeEdit
//

import SwiftUI

struct ExtensionCatalogDetailView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @EnvironmentObject private var installation: ExtensionInstallationViewModel
    @EnvironmentObject private var languageManager: LanguageExtensionManager
    @State private var isConfirmingInstall = false

    let candidate: ExtensionCatalogCandidate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                catalogDetails
                availableVersions
                installationGroup
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirmingInstall,
            titleVisibility: .visible
        ) {
            Button(installActionTitle) { startInstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.entry.name)
                .font(.largeTitle.weight(.semibold))
            Text(candidate.entry.description)
                .font(.body)
                .foregroundStyle(.secondary)
            Label(candidate.entry.publisher, systemImage: "person")
                .font(.subheadline)
        }
    }

    private var catalogDetails: some View {
        GroupBox("Catalog Details") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                detailRow("Extension ID", candidate.extensionID)
                detailRow("Latest Version", candidate.entry.latest)
                detailRow("Source", sourceName)
                if marketplace.isShowingCachedData(for: candidate.sourceID) {
                    detailRow("Catalog Status", "Cached · refresh required")
                }
                if let homepage = candidate.entry.url {
                    GridRow {
                        Text("Website").foregroundStyle(.secondary)
                        Link(homepage.host ?? homepage.absoluteString, destination: homepage)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var availableVersions: some View {
        GroupBox("Available Versions") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(candidate.entry.versions.keys.sorted(by: versionOrder), id: \.self) { version in
                    HStack {
                        Text(version).font(.body.monospaced())
                        if version == candidate.entry.latest {
                            Text("Latest").font(.caption).foregroundStyle(.secondary)
                        }
                        if version == installedExtension?.version {
                            Text("Installed").font(.caption).foregroundStyle(.green)
                        }
                        Spacer()
                        if let publishedAt = candidate.entry.versions[version]?.publishedAt {
                            Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var installationGroup: some View {
        GroupBox("Installation") {
            VStack(alignment: .leading, spacing: 12) {
                installedSummary
                if let installed = installedExtension, installed.version != candidate.version {
                    replacementPreview(installed: installed)
                }
                if let capabilities = installedExtension?.manifest.capabilities, !capabilities.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Capabilities").foregroundStyle(.secondary)
                        Text(capabilities.sorted().joined(separator: " · "))
                            .textSelection(.enabled)
                    }
                }
                Divider()
                installationAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var installedSummary: some View {
        if let installed = installedExtension {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                detailRow("Installed", installed.version ?? "Unknown version")
                detailRow("Installed From", installed.provenance?.sourceName ?? "Local package")
                if installed.version == candidate.version,
                   installed.provenance?.sourceID == candidate.sourceID {
                    detailRow("Status", "Up to date for this source")
                }
            }
        } else {
            Text("This extension is not installed.")
                .foregroundStyle(.secondary)
        }
    }

    private func replacementPreview(installed: InstalledLanguageExtension) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            detailRow("Replace", "\(installed.version ?? "Unknown") → \(candidate.version)")
            detailRow(
                "Source Change",
                installed.provenance?.sourceID == candidate.sourceID
                    ? "No · \(sourceName)"
                    : "\(installed.provenance?.sourceName ?? "Local package") → \(sourceName)"
            )
        }
    }

    @ViewBuilder private var installationAction: some View {
        let state = installation.state(for: candidate.id)
        switch state {
        case .preparing, .downloading, .extracting, .validating, .installing, .cancelling:
            progressView(for: state)
        case .succeeded(let version):
            Label("Version \(version) installed.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .cancelled:
            VStack(alignment: .leading, spacing: 8) {
                Text("Installation was cancelled.")
                    .foregroundStyle(.secondary)
                installButton
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                installButton
            }
        case .idle:
            installButton
        }
    }

    private func progressView(for state: ExtensionInstallationState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progressLabel(for: state))
                    .font(.callout)
            }
            if let fraction = progressFraction(for: state) {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
            }
            if case .downloading(let completed, let total, _) = state {
                Text(byteProgress(completed: completed, total: total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if state != .cancelling {
                Button("Cancel", role: .cancel) {
                    installation.cancel(candidate.id)
                }
            }
        }
    }

    private var installButton: some View {
        Button(installActionTitle) {
            if installedExtension == nil {
                startInstall()
            } else {
                isConfirmingInstall = true
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(marketplace.source(for: candidate.sourceID) == nil)
    }

    private var installActionTitle: String {
        guard let installed = installedExtension else { return "Install \(candidate.version)" }
        let sameSource = installed.provenance?.sourceID == candidate.sourceID
        if installed.version == candidate.version {
            return sameSource ? "Reinstall \(candidate.version)" : "Switch Source and Reinstall"
        }
        return sameSource ? "Update to \(candidate.version)" : "Install \(candidate.version) from \(sourceName)"
    }

    private var confirmationTitle: String {
        guard let installed = installedExtension else { return "Install \(candidate.entry.name)?" }
        let sameSource = installed.provenance?.sourceID == candidate.sourceID
        return sameSource ? "Replace \(candidate.entry.name)?" : "Switch Extension Source?"
    }

    private var confirmationMessage: String {
        guard let installed = installedExtension else {
            return "Install version \(candidate.version) from \(sourceName)?"
        }
        let currentVersion = installed.version ?? "an unknown version"
        let currentSource = installed.provenance?.sourceName ?? "a local package"
        var message = "Replace version \(currentVersion) from \(currentSource) with version " +
            "\(candidate.version) from \(sourceName)?"
        if installed.provenance?.sourceID != candidate.sourceID {
            message += " This changes which source provides the extension."
        }
        if installed.provenance == nil {
            message += " The local package will no longer be marked as locally installed."
        }
        return message
    }

    private var installedExtension: InstalledLanguageExtension? {
        languageManager.extensions.first { $0.id == candidate.extensionID }
    }

    private var sourceName: String {
        marketplace.sourceName(for: candidate.sourceID)
    }

    private func startInstall() {
        guard let source = marketplace.source(for: candidate.sourceID) else { return }
        installation.install(candidate, from: source)
    }
}

extension ExtensionCatalogDetailView {
    private func progressLabel(for state: ExtensionInstallationState) -> String {
        switch state {
        case .preparing: "Preparing installation…"
        case .downloading: "Downloading and verifying package…"
        case .extracting: "Extracting and checking package contents…"
        case .validating: "Validating manifest and compatibility…"
        case .installing: "Installing atomically…"
        case .cancelling: "Cancelling…"
        case .idle, .succeeded, .cancelled, .failed: ""
        }
    }

    private func progressFraction(for state: ExtensionInstallationState) -> Double? {
        switch state {
        case .downloading(_, _, let fraction):
            fraction
        case .extracting(let fraction):
            fraction
        case .preparing, .validating, .installing, .cancelling, .idle, .succeeded, .cancelled, .failed:
            nil
        }
    }

    private func byteProgress(completed: Int64, total: Int64?) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if let total {
            return "\(formatter.string(fromByteCount: completed)) of \(formatter.string(fromByteCount: total))"
        }
        return formatter.string(fromByteCount: completed)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func versionOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == candidate.entry.latest { return true }
        if rhs == candidate.entry.latest { return false }
        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }
}
