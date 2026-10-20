import AppKit
import Combine
import Foundation

extension RunController {
    /// Starts the project's local site and maps the coordinator's outcome onto the run state.
    func performSiteRun(_ configuration: RunConfiguration) {
        guard let coordinator = workspace?.localSiteCoordinator else {
            return
        }
        runningSiteConfigurationID = configuration.id
        runningConfigurationID = configuration.id
        observeSiteState(coordinator)

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

    func observeSiteState(_ coordinator: WorkspaceLocalSiteCoordinator) {
        guard siteStateCancellable == nil else {
            return
        }
        siteStateCancellable = coordinator.$state
            .sink { [weak self] state in
                guard let self, self.runningSiteConfigurationID != nil else {
                    return
                }
                if !state.isRunning && !state.isBusy {
                    self.clearRunningSite()
                }
            }
    }

    /// Opens the configured local site in the default browser.
    func openLocalSite() {
        guard let site = workspace?.workspaceSettingsManager?.settings.site,
              let domain = try? SiteDomain(site.domain),
              let url = LocalSiteAddress.url(
                  domain: domain,
                  https: site.https,
                  portMode: Settings.shared.preferences.localDomains.portMode
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
