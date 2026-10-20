import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct WorkspaceLocalSiteCoordinatorTests {
    private func enabled(domain: String = "app.localhost") -> LocalSiteSettings {
        var settings = LocalSiteSettings()
        settings.enabled = true
        settings.domain = domain
        return settings
    }

    private func makeCoordinator(
        debounceInterval: TimeInterval = 0
    ) -> (WorkspaceLocalSiteCoordinator, FakeLocalSiteOperations) {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)
        let coordinator = WorkspaceLocalSiteCoordinator(
            workspaceURL: URL(filePath: "/tmp/project"),
            runner: runner,
            debounceInterval: debounceInterval
        )
        return (coordinator, operations)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test
    func enablingStartsTheSiteExactlyOnce() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.apply(site: enabled(), runtimes: .init())

        #expect(coordinator.appliedActions == [.start])
        #expect(operations.startCalls == 1)
        #expect(coordinator.state == .running)
    }

    @Test
    func disablingStopsTheSite() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.apply(site: enabled(), runtimes: .init())
        await coordinator.apply(site: .init(), runtimes: .init())

        #expect(coordinator.appliedActions == [.start, .stop])
        #expect(operations.stopCalls == 1)
        #expect(coordinator.state == .idle)
    }

    @Test
    func nginxRefinementReloadsWithoutRestart() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.apply(site: enabled(), runtimes: .init())

        var refined = enabled()
        refined.documentRoot = "public"
        await coordinator.apply(site: refined, runtimes: .init())

        #expect(coordinator.appliedActions == [.start, .reloadNginx])
        #expect(operations.reloadCalls == 1)
        #expect(operations.startCalls == 1)
        #expect(operations.stopCalls == 0)
    }

    @Test
    func phpChangeTriggersASingleRestart() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.apply(site: enabled(), runtimes: .init())

        var changed = enabled()
        changed.phpVersion = "8.4"
        await coordinator.apply(site: changed, runtimes: .init())

        #expect(coordinator.appliedActions == [.start, .restartFPM])
        #expect(operations.startCalls == 2)
        #expect(operations.stopCalls == 1)
        #expect(operations.reloadCalls == 0)
    }

    @Test
    func openInBrowserChangeAppliesNoAction() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.apply(site: enabled(), runtimes: .init())

        var changed = enabled()
        changed.openInBrowser = false
        await coordinator.apply(site: changed, runtimes: .init())

        #expect(coordinator.appliedActions == [.start])
        #expect(operations.reloadCalls == 0)
        #expect(operations.startCalls == 1)
    }

    @Test
    func manualStartAndStopDriveTheRunner() async {
        let (coordinator, operations) = makeCoordinator()

        let result = await coordinator.startSite()

        #expect(result == .started)
        #expect(coordinator.state == .running)
        #expect(operations.startCalls == 1)

        await coordinator.stopSite()

        #expect(coordinator.state == .idle)
        #expect(operations.stopCalls == 1)
    }

    @Test
    func autoStartOnOpenHonorsThePreferenceAndEnabledState() async throws {
        try await withTempDir { directory in
            let manager = CEWorkspaceSettings(workspaceURL: directory)
            manager.settings.site = enabled()
            let (coordinator, operations) = makeCoordinator()
            coordinator.start(settingsManager: manager)

            await coordinator.startIfEnabledOnOpen(autoStart: false)
            #expect(operations.startCalls == 0)

            await coordinator.startIfEnabledOnOpen(autoStart: true)
            #expect(operations.startCalls == 1)
            #expect(coordinator.state == .running)
        }
    }

    @Test
    func autoStartOnOpenIgnoresDisabledSites() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.startIfEnabledOnOpen(autoStart: true)

        #expect(operations.startCalls == 0)
        #expect(coordinator.state == .idle)
    }

    @Test
    func shutdownStopsTheSite() async {
        let (coordinator, operations) = makeCoordinator()

        await coordinator.apply(site: enabled(), runtimes: .init())
        await coordinator.shutdown()

        #expect(coordinator.state == .idle)
        #expect(operations.stopCalls == 1)
    }

    @Test
    func observesLiveSettingsAndAppliesOneActionPerChange() async throws {
        try await withTempDir { directory in
            let manager = CEWorkspaceSettings(workspaceURL: directory)
            let (coordinator, operations) = makeCoordinator()
            coordinator.start(settingsManager: manager)

            manager.settings.site = enabled()
            await waitUntil { operations.startCalls == 1 }

            #expect(operations.startCalls == 1)
            #expect(coordinator.appliedActions == [.start])

            var refined = enabled()
            refined.documentRoot = "public"
            manager.settings.site = refined
            await waitUntil { operations.reloadCalls == 1 }

            #expect(operations.reloadCalls == 1)
            #expect(operations.startCalls == 1)
            #expect(coordinator.appliedActions == [.start, .reloadNginx])
        }
    }
}
