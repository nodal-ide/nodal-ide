import AppKit
import SwiftUI

/// The "Local Domains" section of Developer settings: tool status/install, port mode, and certificate
/// authority trust/reset.
struct LocalDomainsSettingsSection: View {
    @AppSettings(\.localDomains.portMode)
    private var portMode

    @AppSettings(\.localDomains.autoStartSitesOnOpen)
    private var autoStartSitesOnOpen

    @StateObject private var model = LocalDomainsSettingsViewModel()
    @State private var confirmReset = false
    @State private var confirmStateReset = false
    @State private var copiedDiagnostics = false

    var body: some View {
        Group {
            toolsSection
            portModeSection
            startupSection
            authoritySection
            diagnosticsSection
        }
        .task { await model.refresh() }
    }

    private var toolsSection: some View {
        Section {
            toolRow(.nginx, status: model.nginx)
            toolRow(.mkcert, status: model.mkcert)

            if model.brew == .missing {
                Label("Install Homebrew from brew.sh to enable installs.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            HStack {
                Text("Local Server Tools")
                Spacer()
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(model.isBusy)
            }
        } footer: {
            Text("nginx and mkcert are installed with Homebrew; Nodal IDE runs the detected system binaries.")
        }
    }

    private var portModeSection: some View {
        Section {
            Picker("Port Mode", selection: $portMode) {
                ForEach(SettingsData.LocalDomainsSettings.PortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(portMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Ports")
        } footer: {
            Text("Portless mode uses a credential-prompted relay for 80/443; high ports never ask for a password.")
        }
    }

    private var startupSection: some View {
        Section {
            Toggle("Start enabled sites when a workspace opens", isOn: $autoStartSitesOnOpen)
        } header: {
            Text("Startup")
        } footer: {
            Text(
                "When enabled, projects whose local domain is enabled start their site as soon as "
                + "the workspace opens."
            )
        }
    }

    private var authoritySection: some View {
        Section {
            LabeledContent("Certificate Authority") {
                HStack(spacing: 6) {
                    Image(systemName: authoritySymbol)
                        .foregroundStyle(authorityColor)
                    Text(authorityText)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if model.hasLoaded && model.authority.isTrusted {
                    Button("Reset…") {
                        confirmReset = true
                    }
                    .disabled(model.isBusy)
                    .controlSize(.small)
                    .confirmationDialog(
                        "Reset the Nodal IDE certificate authority?",
                        isPresented: $confirmReset,
                        titleVisibility: .visible
                    ) {
                        Button("Reset Authority", role: .destructive) {
                            Task { await model.resetAuthority() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "This removes the trusted certificate from the system keychain and deletes "
                            + "generated certificates. HTTPS sites must trust a new authority."
                        )
                    }
                } else {
                    Button(model.isTrusting ? "Trusting…" : "Trust…") {
                        Task { await model.trustAuthority() }
                    }
                    .disabled(model.isBusy || !model.mkcert.isInstalled)
                    .help(model.mkcert.isInstalled
                          ? "Trust the Nodal IDE CA; macOS asks for your password."
                          : "Install mkcert first.")
                    .controlSize(.small)
                }
                Spacer()
            }
        } header: {
            Text("Certificate Authority")
        } footer: {
            Text(
                "Trusting installs the app-owned CA for .localhost. Reset removes it from the system "
                + "keychain and deletes generated certificates."
            )
        }
    }

    private var diagnosticsSection: some View {
        Section {
            HStack(spacing: 8) {
                Button(copiedDiagnostics ? "Copied" : "Copy Diagnostics") {
                    Task { await copyDiagnostics() }
                }
                .disabled(model.isBusy)

                Button("Reset Generated State…") {
                    confirmStateReset = true
                }
                .disabled(model.isBusy)

                Spacer()
            }

            if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text(
                "Copies tool versions, paths, and recent nginx errors with your home folder redacted. "
                + "Reset removes generated nginx configs, logs, temp files, and certificates; the "
                + "certificate authority is kept."
            )
        }
        .confirmationDialog(
            "Reset generated proxy state?",
            isPresented: $confirmStateReset,
            titleVisibility: .visible
        ) {
            Button("Reset Generated State", role: .destructive) {
                Task { await model.resetGeneratedState() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Running sites stop first. Certificate files are deleted and reissued on the next start.")
        }
    }

    private func copyDiagnostics() async {
        let report = await model.diagnosticsReport(portMode: portMode)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copiedDiagnostics = true
        try? await Task.sleep(for: .seconds(2))
        copiedDiagnostics = false
    }

    private func toolRow(_ tool: LocalServerTool, status: LocalServerToolStatus) -> some View {
        LabeledContent(tool.title) {
            HStack(spacing: 8) {
                Text(statusText(status))
                    .foregroundStyle(status.isInstalled ? .secondary : .primary)

                switch status {
                case .installed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .missing:
                    Button(model.busyTool == tool ? "Installing…" : "Install") {
                        Task { await model.install(tool) }
                    }
                    .disabled(model.isBusy || !model.brewAvailable)
                    .help(model.brewAvailable ? "Install with Homebrew." : "Install Homebrew first (brew.sh).")
                    .controlSize(.small)
                case .unknown:
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func statusText(_ status: LocalServerToolStatus) -> String {
        switch status {
        case .unknown: return "Checking…"
        case .missing: return "Not installed"
        case .installed(let installation):
            return installation.version.isEmpty ? "Installed" : installation.version
        }
    }

    private var authorityText: String {
        guard model.hasLoaded else {
            return "Checking…"
        }
        switch model.authority {
        case .missing: return "Not created"
        case .present(trusted: true): return "Trusted"
        case .present(trusted: false): return "Not trusted"
        }
    }

    private var authoritySymbol: String {
        guard model.hasLoaded else {
            return "clock"
        }
        switch model.authority {
        case .missing: return "xmark.circle"
        case .present(trusted: true): return "checkmark.circle.fill"
        case .present(trusted: false): return "exclamationmark.triangle.fill"
        }
    }

    private var authorityColor: Color {
        guard model.hasLoaded else {
            return .secondary
        }
        switch model.authority {
        case .missing: return .orange
        case .present(trusted: true): return .green
        case .present(trusted: false): return .orange
        }
    }
}
