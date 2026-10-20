//
//  WorkspaceSettingsLocalDomainView.swift
//  CodeEdit
//
//  The "Local Domain" page of the Project Settings window.
//

import SwiftUI

struct WorkspaceSettingsLocalDomainView: View {
    @AppSettings(\.localDomains.portMode)
    private var portMode

    @EnvironmentObject private var workspaceSettingsManager: CEWorkspaceSettings
    @EnvironmentObject private var workspace: WorkspaceDocument

    @State private var draft: LocalDomainSettingsDraft
    @State private var usableRuntimes: [LocalSiteRuntime] = []
    @State private var runtimesLoaded = false
    @StateObject private var preflight = SitePreflightViewModel()

    init(site: LocalSiteSettings) {
        _draft = State(initialValue: LocalDomainSettingsDraft(site: site))
    }

    var body: some View {
        Form {
            siteStatusSection
            preflightSection
            availabilitySection
            addressSection
            contentSection
            if site.handler == .phpFPM {
                phpSection
            }
            if site.handler == .proxy {
                proxySection
            }
            securitySection
        }
        .formStyle(.grouped)
        .navigationTitle("Local Domain")
        .task {
            await loadRuntimes()
            await preflight.refresh(site: site)
        }
        .onChange(of: site.https) { _, _ in refreshPreflight() }
        .onChange(of: site.phpVersion) { _, _ in refreshPreflight() }
    }
}

extension WorkspaceSettingsLocalDomainView {
    // MARK: - Sections

    private var siteStatusSection: some View {
        Section {
            if let coordinator = workspace.localSiteCoordinator {
                LocalDomainStatusCard(coordinator: coordinator, url: siteURL)
            } else {
                Text("The local site service is unavailable for this workspace.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Site")
        }
    }

    private var preflightSection: some View {
        Section {
            SitePreflightChecklist(model: preflight, site: site)
        } header: {
            HStack {
                Text("Before You Start")
                Spacer()
                Button("Refresh") {
                    refreshPreflight()
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(preflight.isBusy)
            }
        } footer: {
            Text("Install actions use Homebrew; Trust asks for your password once.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var availabilitySection: some View {
        Section {
            Toggle("Enable local domain", isOn: enabledBinding)
        } header: {
            Text("Availability")
        } footer: {
            Text("The domain is available while the local proxy is running. Nothing is exposed to the network.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var addressSection: some View {
        Section {
            LabeledContent("Domain") {
                TextField("Domain", text: textBinding(\.domain), prompt: Text(suggestedDomain))
                    .labelsHidden()
                    .fontDesign(.monospaced)
                    .multilineTextAlignment(.trailing)
            }
            fieldIssue(.domain)
        } header: {
            Text("Address")
        } footer: {
            Text("Only .localhost domains are supported; they resolve on this Mac without editing /etc/hosts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contentSection: some View {
        Section {
            Picker("Handler", selection: handlerBinding) {
                ForEach(LocalSiteHandler.allCases) { handler in
                    Label(handler.title, systemImage: handler.systemImage).tag(handler)
                }
            }

            if site.handler != .proxy {
                LabeledContent("Document Root") {
                    TextField("Document Root", text: textBinding(\.documentRoot), prompt: Text("Project root"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                fieldIssue(.documentRoot)
            }

            if site.handler == .phpFPM {
                Picker("Routing", selection: routingBinding) {
                    ForEach(LocalSiteRouting.allCases) { routing in
                        Text(routing.title).tag(routing)
                    }
                }

                if site.routing == .frontController {
                    LabeledContent("Entry File") {
                        TextField("Entry File", text: textBinding(\.entryFile), prompt: Text("index.php"))
                            .labelsHidden()
                            .fontDesign(.monospaced)
                            .multilineTextAlignment(.trailing)
                    }
                    fieldIssue(.entryFile)
                }
            }
        } header: {
            Text("Content")
        } footer: {
            Text(contentFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var phpSection: some View {
        Section {
            LabeledContent("PHP Version") {
                runtimeMenu
            }
            fieldIssue(.runtime)
            if runtimesLoaded && usableRuntimes.isEmpty {
                Label(
                    "No PHP runtime with PHP-FPM was found. Install one in the Runtime Manager.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("PHP")
        } footer: {
            Text("Only installed PHP versions with a matching php-fpm are listed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var proxySection: some View {
        Section {
            LabeledContent("Port") {
                TextField("Port", text: textBinding(\.proxyPort), prompt: Text("9000"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            fieldIssue(.port)
            LabeledContent("Start Command") {
                TextField("Start Command", text: textBinding(\.proxyStartCommand), prompt: Text("Optional"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Working Directory") {
                TextField(
                    "Working Directory",
                    text: textBinding(\.proxyWorkingDirectory),
                    prompt: Text("Project root")
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Reverse Proxy")
        } footer: {
            Text(
                "Requests are forwarded to 127.0.0.1:<port>. The optional start command runs in the "
                + "working directory when the site starts. If the dev server rejects the domain, add "
                + "it to the server's allowed hosts (for example Vite server.allowedHosts or Next.js "
                + "allowedDevOrigins)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Use HTTPS", isOn: httpsBinding)
        } header: {
            Text("Security")
        } footer: {
            Text("A locally trusted certificate for the domain is created the first time the site starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Runtime Menu

    private var runtimeMenu: some View {
        Menu {
            Button {
                setPHPVersion(nil)
            } label: {
                menuLabel("Automatic (newest with FPM)", selected: site.phpVersion == nil)
            }

            Divider()

            ForEach(usableRuntimes) { runtime in
                Button {
                    setPHPVersion(runtime.version)
                } label: {
                    menuLabel(
                        "v\(runtime.version) — \(runtime.source.title)",
                        selected: site.phpVersion == runtime.version
                    )
                }
            }

            if let version = site.phpVersion, !isVersionAvailable(version) {
                Divider()
                Button {} label: {
                    menuLabel("v\(version) — not available", selected: true, warning: true)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(site.phpVersion.map { "v\($0)" } ?? "Automatic")
                    .foregroundStyle(site.phpVersion == nil ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func menuLabel(_ text: String, selected: Bool, warning: Bool = false) -> some View {
        HStack {
            if warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(text)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    // MARK: - Bindings

    private var site: LocalSiteSettings {
        workspaceSettingsManager.settings.site
    }

    private var issues: [SiteValidationIssue] {
        draft.issues(
            for: site,
            workspaceURL: workspace.fileURL,
            availablePHPVersions: runtimesLoaded ? Set(usableRuntimes.map(\.version)) : nil
        )
    }

    private var siteURL: URL? {
        guard issues.isEmpty, let domain = try? SiteDomain(site.domain) else { return nil }
        return LocalSiteAddress.url(domain: domain, https: site.https, portMode: portMode)
    }

    private var suggestedDomain: String {
        let projectName = workspaceSettingsManager.settings.project.projectName
        return SiteDomain.suggested(from: projectName.isEmpty ? "project" : projectName).value
    }

    private var contentFooter: String {
        if site.handler == .proxy {
            return "Traffic is forwarded to the port below; no files are served from disk."
        }
        return "Path values are relative to the project root. Leave the document root empty to serve the project root."
    }

    private func textBinding(_ keyPath: WritableKeyPath<LocalDomainSettingsDraft, String>) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath]
        } set: { newValue in
            draft[keyPath: keyPath] = newValue
            saveDraft()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            site.enabled
        } set: { newValue in
            if newValue, draft.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.domain = suggestedDomain
                saveDraft()
            }
            update { $0.enabled = newValue }
        }
    }

    private var httpsBinding: Binding<Bool> {
        Binding { site.https } set: { newValue in update { $0.https = newValue } }
    }

    private var handlerBinding: Binding<LocalSiteHandler> {
        Binding { site.handler } set: { newValue in update { $0.handler = newValue } }
    }

    private var routingBinding: Binding<LocalSiteRouting> {
        Binding { site.routing } set: { newValue in update { $0.routing = newValue } }
    }

    // MARK: - Actions

    private func saveDraft() {
        workspaceSettingsManager.settings.site = draft.applying(to: site)
    }

    private func update(_ transform: (inout LocalSiteSettings) -> Void) {
        var current = workspaceSettingsManager.settings.site
        transform(&current)
        workspaceSettingsManager.settings.site = current
    }

    private func setPHPVersion(_ version: String?) {
        update { $0.phpVersion = version }
    }

    private func isVersionAvailable(_ version: String) -> Bool {
        usableRuntimes.contains { $0.version == version }
    }

    private func refreshPreflight() {
        Task { await preflight.refresh(site: site) }
    }

    private func loadRuntimes() async {
        guard let provider = AppServices.runtimeManager.provider(for: .php) else {
            runtimesLoaded = true
            return
        }
        usableRuntimes = await PHPFPMRuntimeCatalog().usableRuntimes(using: provider)
        runtimesLoaded = true
    }

    @ViewBuilder
    private func fieldIssue(_ field: SiteValidationIssue.Field) -> some View {
        if let issue = issues.first(where: { $0.field == field }) {
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel("Warning: \(issue.message)")
        }
    }
}
