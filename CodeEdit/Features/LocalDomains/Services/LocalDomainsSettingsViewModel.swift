import Foundation

/// Backs the Local Domains section in Developer settings: tool discovery, Homebrew installs, and
/// certificate-authority trust/reset.
@MainActor
final class LocalDomainsSettingsViewModel: ObservableObject {
    @Published private(set) var nginx: LocalServerToolStatus
    @Published private(set) var mkcert: LocalServerToolStatus
    @Published private(set) var brew: LocalServerToolStatus
    @Published private(set) var authority: CertificateAuthorityStatus = .missing
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var busyTool: LocalServerTool?
    @Published private(set) var isTrusting = false
    @Published private(set) var isResetting = false
    @Published private(set) var isResettingState = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let tooling: LocalServerTooling
    private let certificateAuthority: any CertificateProviding
    private let diagnostics: LocalDomainsDiagnostics

    init(
        tooling: LocalServerTooling? = nil,
        authority: (any CertificateProviding)? = nil,
        diagnostics: LocalDomainsDiagnostics? = nil
    ) {
        let tooling = tooling ?? AppServices.localProxy.tooling
        let certificateAuthority = authority ?? CertificateAuthority(tooling: tooling)
        self.tooling = tooling
        self.certificateAuthority = certificateAuthority
        self.diagnostics = diagnostics ?? LocalDomainsDiagnostics(
            tooling: tooling,
            authority: certificateAuthority
        )
        self.nginx = tooling.nginx
        self.mkcert = tooling.mkcert
        self.brew = tooling.brew
    }

    var isBusy: Bool {
        isRefreshing || busyTool != nil || isTrusting || isResetting || isResettingState
    }

    var brewAvailable: Bool {
        brew.isInstalled
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true

        await tooling.refresh(force: true)
        await reloadAuthorityAndSync()

        isRefreshing = false
        hasLoaded = true
    }

    func install(_ tool: LocalServerTool) async {
        guard tool != .brew, busyTool == nil else {
            return
        }
        busyTool = tool
        errorMessage = nil

        do {
            try await tooling.install(tool)
        } catch {
            errorMessage = Self.message(for: error)
        }

        busyTool = nil
        await reloadAuthorityAndSync()
    }

    func trustAuthority() async {
        guard !isTrusting else {
            return
        }
        isTrusting = true
        errorMessage = nil

        do {
            try await certificateAuthority.trustAuthority()
        } catch {
            errorMessage = Self.message(for: error)
        }

        isTrusting = false
        await reloadAuthorityAndSync()
    }

    func resetAuthority() async {
        guard !isResetting else {
            return
        }
        isResetting = true
        errorMessage = nil

        do {
            try await certificateAuthority.resetAuthority()
        } catch {
            errorMessage = Self.message(for: error)
        }

        isResetting = false
        await reloadAuthorityAndSync()
    }

    func diagnosticsReport(portMode: SettingsData.LocalDomainsSettings.PortMode) async -> String {
        await diagnostics.report(portMode: portMode, lastError: errorMessage)
    }

    func resetGeneratedState() async {
        guard !isResettingState else {
            return
        }
        isResettingState = true
        errorMessage = nil
        statusMessage = nil

        do {
            try await diagnostics.resetGeneratedState()
            statusMessage = "Generated nginx state and certificates were removed."
        } catch {
            errorMessage = Self.message(for: error)
        }

        isResettingState = false
        await reloadAuthorityAndSync()
    }

    private func reloadAuthorityAndSync() async {
        authority = await certificateAuthority.authorityStatus()
        nginx = tooling.nginx
        mkcert = tooling.mkcert
        brew = tooling.brew
    }

    private static func message(for error: Error) -> String {
        guard let localized = error as? LocalizedError else {
            return error.localizedDescription
        }
        guard let suggestion = localized.recoverySuggestion, !suggestion.isEmpty else {
            return localized.localizedDescription
        }
        return "\(localized.localizedDescription) \(suggestion)"
    }
}
