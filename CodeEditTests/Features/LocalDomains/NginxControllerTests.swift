import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxControllerTests {
    private struct LaunchFailure: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    private let executableURL = URL(filePath: "/opt/homebrew/bin/nginx")
    private let configURL = URL(filePath: "/tmp/nginx-test.conf")

    private func makeController(
        prober: FakePortProber,
        launcher: FakeProcessLauncher? = nil,
        validator: FakeNginxConfigValidator? = nil,
        timeSource: FakeTimeSource = FakeTimeSource(),
        prefix: NginxPrefix = NginxPrefix(root: URL(filePath: "/tmp/nginx-test", directoryHint: .isDirectory))
    ) -> NginxController {
        NginxController(
            launcher: launcher ?? FakeProcessLauncher(),
            prober: prober,
            validator: validator ?? FakeNginxConfigValidator(),
            timeSource: timeSource,
            prefix: prefix,
            readinessTimeout: .milliseconds(100),
            stopTimeout: .seconds(1)
        )
    }

    private func site(domain: String) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: domain,
            listenPort: 18080,
            documentRootPath: "/tmp/\(domain)-root",
            upstream: .staticFiles,
            routing: .directory,
            entryFile: "index.php",
            accessLogPath: "/tmp/\(domain)-access.log",
            errorLogPath: "/tmp/\(domain)-error.log"
        )
    }

    @Test
    func reportsBusyPortWithoutLaunchingOrKilling() async {
        let launcher = FakeProcessLauncher()
        let controller = makeController(prober: FakePortProber(results: [true]), launcher: launcher)

        await #expect(throws: NginxControllerError.portInUse(18080)) {
            try await controller.start(
                executableURL: executableURL,
                configURL: configURL,
                listenPorts: [18080]
            )
        }

        #expect(launcher.launches.isEmpty)
        #expect(controller.state == .stopped)
    }

    @Test
    func startsAndReportsRunningOnceReady() async throws {
        let launcher = FakeProcessLauncher()
        let controller = makeController(prober: FakePortProber(results: [false, true]), launcher: launcher)

        try await controller.start(
            executableURL: executableURL,
            configURL: configURL,
            listenPorts: [18080]
        )

        #expect(controller.isRunning)
        #expect(controller.pid == 1)
        #expect(controller.state == .running(pid: 1))
        #expect(launcher.launches.count == 1)
        #expect(launcher.launches.first?.request.arguments == [
            "-p", "/tmp/nginx-test/", "-c", "/tmp/nginx-test.conf"
        ])
    }

    @Test
    func reportsLaunchFailure() async {
        let launcher = FakeProcessLauncher()
        launcher.launchError = LaunchFailure()
        let controller = makeController(prober: FakePortProber(results: [false]), launcher: launcher)

        await #expect(throws: NginxControllerError.launchFailed(message: "boom")) {
            try await controller.start(
                executableURL: executableURL,
                configURL: configURL,
                listenPorts: [18080]
            )
        }

        #expect(controller.state == .failed(.launchFailed(message: "boom")))
    }

    @Test
    func timesOutAndStopsWhenNeverReady() async {
        let launcher = FakeProcessLauncher()
        let controller = makeController(prober: FakePortProber(results: [false]), launcher: launcher)

        await #expect(throws: NginxControllerError.readinessTimedOut(port: 18080)) {
            try await controller.start(
                executableURL: executableURL,
                configURL: configURL,
                listenPorts: [18080]
            )
        }

        #expect(controller.state == .failed(.readinessTimedOut(port: 18080)))
        #expect(launcher.launches.first?.process.receivedStops.first?.signal == ProcessSignal.quit)
    }

    @Test
    func reportsProcessExitDuringStartup() async {
        let launcher = FakeProcessLauncher()
        let prober = FakePortProber(results: [false])
        prober.onProbe = { index in
            if index == 1 {
                launcher.launches.last?.process.finish(ProcessExit(status: 2, reason: .exited))
            }
        }
        let controller = makeController(prober: prober, launcher: launcher)

        await #expect(throws: NginxControllerError.exitedDuringStartup(status: 2, message: "")) {
            try await controller.start(
                executableURL: executableURL,
                configURL: configURL,
                listenPorts: [18080]
            )
        }

        #expect(controller.state == .failed(.exitedDuringStartup(status: 2, message: "")))
    }

    @Test
    func stopSignalsQuitAndClearsTheProcess() async throws {
        let launcher = FakeProcessLauncher()
        let controller = makeController(prober: FakePortProber(results: [false, true]), launcher: launcher)

        try await controller.start(
            executableURL: executableURL,
            configURL: configURL,
            listenPorts: [18080]
        )
        await controller.stop()

        #expect(!controller.isRunning)
        #expect(controller.pid == nil)
        #expect(controller.state == .stopped)
        #expect(launcher.launches.first?.process.receivedStops.first?.signal == ProcessSignal.quit)
    }
}
