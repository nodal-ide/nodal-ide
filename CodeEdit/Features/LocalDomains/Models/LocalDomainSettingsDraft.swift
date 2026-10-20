import Foundation

/// Editable text buffers for the Local Domain settings page.
///
/// The page binds text fields to this value rather than directly to `LocalSiteSettings` so that
/// committing a keystroke does not rebuild the settings tree and steal focus. `applying(to:)` writes
/// the buffers back; `issues(for:)` explains every value the runner would reject.
struct LocalDomainSettingsDraft: Equatable {
    var domain: String
    var documentRoot: String
    var entryFile: String
    var proxyPort: String
    var proxyStartCommand: String
    var proxyWorkingDirectory: String

    init(site: LocalSiteSettings = .init()) {
        self.domain = site.domain
        self.documentRoot = site.documentRoot
        self.entryFile = site.entryFile
        self.proxyPort = String(site.proxy.port)
        self.proxyStartCommand = site.proxy.startCommand
        self.proxyWorkingDirectory = site.proxy.workingDirectory
    }

    /// Returns a copy of `site` with the edited values. A valid bare name is normalized to `.localhost`;
    /// an unparsable port keeps the previous value so the settings file never stores nonsense.
    func applying(to site: LocalSiteSettings) -> LocalSiteSettings {
        var site = site
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized = try? SiteDomain(trimmedDomain) {
            site.domain = normalized.value
        } else {
            site.domain = trimmedDomain
        }
        site.documentRoot = documentRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        site.entryFile = entryFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if let port = Int(proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)) {
            site.proxy.port = port
        }
        site.proxy.startCommand = proxyStartCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        site.proxy.workingDirectory = proxyWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return site
    }

    func issues(
        for site: LocalSiteSettings,
        workspaceURL: URL?,
        availablePHPVersions: Set<String>? = nil
    ) -> [SiteValidationIssue] {
        var issues = domainIssues(enabled: site.enabled)

        if site.handler != .proxy, let issue = documentRootIssue(workspaceURL: workspaceURL) {
            issues.append(issue)
        }

        if site.handler == .phpFPM {
            if let issue = entryFileIssue(site: site, workspaceURL: workspaceURL) {
                issues.append(issue)
            }
            if let version = site.phpVersion,
               let available = availablePHPVersions,
               !available.contains(version) {
                issues.append(SiteValidationIssue(
                    field: .runtime,
                    message: "PHP \(version) is not available with PHP-FPM. Choose an installed version.",
                    recoveryAction: .installPHP
                ))
            }
        }

        if site.handler == .proxy, let issue = proxyPortIssue() {
            issues.append(issue)
        }

        return issues
    }

    // MARK: - Validation

    private func domainIssues(enabled: Bool) -> [SiteValidationIssue] {
        let value = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            guard enabled else { return [] }
            return [SiteValidationIssue(
                field: .domain,
                message: "Enter a local domain.",
                recoveryAction: .editDomain
            )]
        }
        do {
            _ = try SiteDomain(value)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Enter a valid domain ending in .localhost."
            return [SiteValidationIssue(field: .domain, message: message, recoveryAction: .editDomain)]
        }
        return []
    }

    private func documentRootIssue(workspaceURL: URL?) -> SiteValidationIssue? {
        let path = documentRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        if path.hasPrefix("/") || path.hasPrefix("~") || path.split(separator: "/").contains("..") {
            return SiteValidationIssue(
                field: .documentRoot,
                message: LocalSiteError.documentRootOutsideWorkspace.localizedDescription,
                recoveryAction: .editDocumentRoot
            )
        }

        guard let workspaceURL else { return nil }
        let url = workspaceURL.appending(path: path, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else {
            return SiteValidationIssue(
                field: .documentRoot,
                message: LocalSiteError.documentRootMissing(path).localizedDescription,
                recoveryAction: .editDocumentRoot
            )
        }
        return nil
    }

    private func entryFileIssue(site: LocalSiteSettings, workspaceURL: URL?) -> SiteValidationIssue? {
        let file = entryFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !file.isEmpty else {
            return SiteValidationIssue(
                field: .entryFile,
                message: "Enter an entry file, for example index.php.",
                recoveryAction: .editEntryFile
            )
        }
        do {
            try NginxConfigValidation.validate(entryFile: file)
        } catch {
            return SiteValidationIssue(
                field: .entryFile,
                message: "Use a .php file name with letters, numbers, dots, dashes, or underscores.",
                recoveryAction: .editEntryFile
            )
        }

        guard site.routing == .frontController, let rootURL = documentRootURL(workspaceURL: workspaceURL) else {
            return nil
        }
        let entryURL = rootURL.appending(path: file)
        guard !FileManager.default.fileExists(atPath: entryURL.path(percentEncoded: false)) else {
            return nil
        }
        return SiteValidationIssue(
            field: .entryFile,
            message: LocalSiteError.entryFileMissing(file).localizedDescription,
            recoveryAction: .editEntryFile
        )
    }

    private func proxyPortIssue() -> SiteValidationIssue? {
        let value = proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(value) else {
            return SiteValidationIssue(
                field: .port,
                message: "Enter a port number between 1 and 65535.",
                recoveryAction: .changePort
            )
        }
        guard (1...65535).contains(port) else {
            return SiteValidationIssue(
                field: .port,
                message: "Use a port between 1 and 65535.",
                recoveryAction: .changePort
            )
        }
        return nil
    }

    private func documentRootURL(workspaceURL: URL?) -> URL? {
        guard let workspaceURL else { return nil }
        let path = documentRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return workspaceURL }
        guard !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.split(separator: "/").contains("..") else {
            return nil
        }
        return workspaceURL.appending(path: path, directoryHint: .isDirectory)
    }
}
