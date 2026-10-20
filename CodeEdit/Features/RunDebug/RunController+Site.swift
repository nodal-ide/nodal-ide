import AppKit
import Combine
import Foundation

extension RunController {
    var siteConfiguration: RunConfiguration? {
        configurations.first { $0.kind == .site }
    }

    var isLocalSiteEnabled: Bool {
        workspace?.workspaceSettingsManager?.settings.site.enabled == true
    }

    var canRunLocalSite: Bool {
        isLocalSiteEnabled && !localSiteState.isRunning && !localSiteState.isBusy
    }

    var canStopLocalSite: Bool {
        isLocalSiteEnabled && (localSiteState.isRunning || localSiteState.failure != nil)
    }

    /// Runs the project's local site without requiring the user to find the generated Site
    /// configuration first.
    func runLocalSite() {
        if let siteConfiguration {
            run(siteConfiguration)
            return
        }
        guard let coordinator = workspace?.localSiteCoordinator else { return }
        Task { await coordinator.startSite() }
    }

    /// Stops the local site even when it was started outside the Run menu.
    func stopLocalSite() {
        guard let coordinator = workspace?.localSiteCoordinator else { return }
        clearRunningSite()
        Task { await coordinator.stopSite() }
    }

    /// Keeps the Run menu, status, and generated Site configuration in sync with the workspace's
    /// local site. Called once by `WorkspaceServices` after the coordinator is created.
    func bindLocalSite(
        _ coordinator: WorkspaceLocalSiteCoordinator,
        settingsManager: CEWorkspaceSettings
    ) {
        boundSiteCoordinator = coordinator
        localSiteState = coordinator.state

        siteStateCancellable = coordinator.$state
            .sink { [weak self] state in
                guard let self else { return }
                self.localSiteState = state
                guard self.runningSiteConfigurationID != nil,
                      !state.isRunning,
                      !state.isBusy else {
                    return
                }
                self.clearRunningSite()
            }

        siteSettingsCancellable = settingsManager.settings.$site
            .map(\.enabled)
            .removeDuplicates()
            .sink { [weak self] _ in self?.installSiteConfigurationIfNeeded() }
    }

    /// Starts the project's local site and maps the coordinator's outcome onto the run state.
    func performSiteRun(_ configuration: RunConfiguration) {
        guard let coordinator = workspace?.localSiteCoordinator else {
            return
        }
        if boundSiteCoordinator !== coordinator, let settingsManager = workspace?.workspaceSettingsManager {
            bindLocalSite(coordinator, settingsManager: settingsManager)
        }
        runningSiteConfigurationID = configuration.id
        runningConfigurationID = configuration.id

        Task { [weak self] in
            let result = await coordinator.startSite()
            guard let self, self.runningSiteConfigurationID == configuration.id else {
                return
            }
            switch result {
            case .started, .alreadyRunning:
                break
            case .failed, .cancelled, .ignoredWhileBusy:
                self.clearRunningSite()
            }
        }
    }

    /// Creates the default "Site" configuration the first time the local domain becomes available.
    /// If it is the only configuration, it also becomes the default target for ⌃⌥R.
    private func installSiteConfigurationIfNeeded() {
        guard isLocalSiteEnabled, let store = workspace?.runConfigurationStore else {
            return
        }
        let configuration = store.ensureSiteConfiguration()
        if selectedConfigurationID == nil {
            selectedConfigurationID = configuration.id
        }
    }

    /// Opens the configured local site in the default browser.
    func openLocalSite() {
        guard let site = workspace?.workspaceSettingsManager?.settings.site,
              let domain = try? SiteDomain(site.domain),
              let url = LocalSiteAddress.url(
                  domain: domain,
                  https: site.https,
                  portMode: AppServices.settings.preferences.localDomains.portMode
              ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func clearRunningSite() {
        runningSiteConfigurationID = nil
        runningConfigurationID = nil
    }

}
