import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxControllerGenerationTests {
    private let executableURL = URL(filePath: "/opt/homebrew/bin/nginx")

    private func makeController(
        prober: FakePortProber,
        launcher: FakeProcessLauncher? = nil,
        validator: FakeNginxConfigValidator? = nil,
        prefix: NginxPrefix,
        timeSource: FakeTimeSource = FakeTimeSource()
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

    private func makePrefix(in directory: URL) throws -> NginxPrefix {
        let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
        try prefix.createDirectories()
        return prefix
    }

    @Test
    func applyStartsFromTheCurrentSymlinkWhenStopped() async throws {
        try await withTempDir { directory in
            let prefix = try makePrefix(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = makeController(
                prober: FakePortProber(results: [false, true]),
                launcher: launcher,
                prefix: prefix
            )

            try await controller.apply(
                executableURL: executableURL,
                sites: [site(domain: "one.localhost")],
                listenPorts: [18080]
            )

            #expect(controller.isRunning)
            #expect(controller.currentGenerationName == "1")
            #expect(launcher.launches.first?.request.arguments.last ==
                prefix.currentSymlink.appending(path: "nginx.conf").path(percentEncoded: false))
        }
    }

    @Test
    func applyReloadsWithoutRestartingTheNginxProcess() async throws {
        try await withTempDir { directory in
            let prefix = try makePrefix(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = makeController(
                prober: FakePortProber(results: [false, true]),
                launcher: launcher,
                prefix: prefix
            )

            try await controller.apply(
                executableURL: executableURL,
                sites: [site(domain: "one.localhost")],
                listenPorts: [18080]
            )
            let pid = controller.pid
            #expect(pid != nil)

            try await controller.apply(
                executableURL: executableURL,
                sites: [site(domain: "two.localhost")],
                listenPorts: [18080]
            )

            #expect(controller.pid == pid)
            #expect(launcher.launches.count == 1)
            #expect(controller.currentGenerationName == "2")
            #expect(launcher.launches.first?.process.receivedSignals == [ProcessSignal.hangup])

            let names = try NginxGenerationStore(prefix: prefix).generationNames().sorted()
            #expect(names == ["1", "2"])
        }
    }

    @Test
    func aRejectedGenerationLeavesThePreviousOneLive() async throws {
        try await withTempDir { directory in
            let prefix = try makePrefix(in: directory)
            let launcher = FakeProcessLauncher()
            let validator = FakeNginxConfigValidator()
            let controller = makeController(
                prober: FakePortProber(results: [false, true]),
                launcher: launcher,
                validator: validator,
                prefix: prefix
            )

            try await controller.apply(
                executableURL: executableURL,
                sites: [site(domain: "one.localhost")],
                listenPorts: [18080]
            )
            validator.result = .invalid(message: "unknown directive")

            await #expect(throws: NginxControllerError.validationFailed(message: "unknown directive")) {
                try await controller.apply(
                    executableURL: executableURL,
                    sites: [site(domain: "two.localhost")],
                    listenPorts: [18080]
                )
            }

            #expect(controller.currentGenerationName == "1")
            #expect(controller.isRunning)
            #expect(launcher.launches.first?.process.receivedSignals.isEmpty == true)

            #expect(try NginxGenerationStore(prefix: prefix).generationNames() == ["1"])
        }
    }

    @Test
    func aStartFailureAfterPublishingRestoresThePreviousGeneration() async throws {
        try await withTempDir { directory in
            let prefix = try makePrefix(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = makeController(
                prober: FakePortProber(results: [true]),
                launcher: launcher,
                prefix: prefix
            )

            await #expect(throws: NginxControllerError.portInUse(18080)) {
                try await controller.apply(
                    executableURL: executableURL,
                    sites: [site(domain: "one.localhost")],
                    listenPorts: [18080]
                )
            }

            #expect(controller.currentGenerationName == nil)
            #expect(try NginxGenerationStore(prefix: prefix).generationNames().isEmpty)
        }
    }

    @Test
    func rotatingLogsRenamesTheFileAndReopensTheProcess() async throws {
        try await withTempDir { directory in
            let launcher = FakeProcessLauncher()
            let controller = makeController(
                prober: FakePortProber(results: [false, true]),
                launcher: launcher,
                prefix: try makePrefix(in: directory)
            )
            try await controller.start(
                executableURL: executableURL,
                configURL: URL(filePath: "/tmp/nginx-test.conf"),
                listenPorts: [18080]
            )

            let logURL = directory.appending(path: "app.access.log")
            try Data(repeating: 0x61, count: 2048).write(to: logURL)

            let rotated = try controller.rotateLogs([logURL], maxBytes: 1024)

            #expect(rotated == [logURL])
            #expect(FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false) + ".1"))
            #expect(launcher.launches.first?.process.receivedSignals == [ProcessSignal.reopen])
        }
    }

    @Test
    func rotatingUnderTheThresholdDoesNotSignal() async throws {
        try await withTempDir { directory in
            let launcher = FakeProcessLauncher()
            let controller = makeController(
                prober: FakePortProber(results: [false, true]),
                launcher: launcher,
                prefix: try makePrefix(in: directory)
            )
            try await controller.start(
                executableURL: executableURL,
                configURL: URL(filePath: "/tmp/nginx-test.conf"),
                listenPorts: [18080]
            )

            let logURL = directory.appending(path: "app.access.log")
            try Data(repeating: 0x61, count: 16).write(to: logURL)

            let rotated = try controller.rotateLogs([logURL], maxBytes: 1024)

            #expect(rotated.isEmpty)
            #expect(launcher.launches.first?.process.receivedSignals.isEmpty == true)
        }
    }

    @Test
    func reopenLogsWithoutAProcessIsHarmless() {
        let controller = NginxController(prober: FakePortProber(), prefix: .default)
        controller.reopenLogs()
        #expect(controller.pid == nil)
    }
}
