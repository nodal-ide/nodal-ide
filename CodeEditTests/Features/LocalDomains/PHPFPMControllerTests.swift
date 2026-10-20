import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PHPFPMControllerTests {
    @Test
    func startsWritesTheConfigAndBecomesReady() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = self.controller(launcher: launcher, prober: FakeUnixSocketProber(results: [false, true]))

            try await controller.start(runtime)

            #expect(controller.state == .running(pid: 1))
            #expect(controller.isRunning)
            #expect(controller.pid == 1)
            let request = try #require(launcher.launches.first?.request)
            #expect(request.executableURL == runtime.executableURL)
            #expect(request.arguments == ["-F", "-y", runtime.configurationURL.path(percentEncoded: false)])
            let config = try String(contentsOf: runtime.configurationURL, encoding: .utf8)
            #expect(config.contains("[www]"))
            #expect(config.contains("listen = \(runtime.pool.socketPath)"))
        }
    }

    @Test
    func refusesToClobberAForeignSocket() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: URL(filePath: runtime.pool.socketPath))

            let launcher = FakeProcessLauncher()
            let controller = self.controller(launcher: launcher, prober: FakeUnixSocketProber(results: [true]))

            await #expect(throws: PHPFPMControllerError.socketInUse(runtime.pool.socketPath)) {
                try await controller.start(runtime)
            }
            #expect(launcher.launches.isEmpty)
            #expect(controller.state == .failed(.socketInUse(runtime.pool.socketPath)))
        }
    }

    @Test
    func removesAStaleSocketBeforeStarting() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: URL(filePath: runtime.pool.socketPath))

            let controller = self.controller(
                launcher: FakeProcessLauncher(),
                prober: FakeUnixSocketProber(results: [false, true])
            )

            try await controller.start(runtime)

            #expect(controller.state == .running(pid: 1))
            #expect(!FileManager.default.fileExists(atPath: runtime.pool.socketPath))
        }
    }

    @Test
    func reportsAProcessThatExitsDuringStartup() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let prober = FakeUnixSocketProber(results: [false])
            prober.onProbe = { _ in
                launcher.launches.last?.process.finish(ProcessExit(status: 1, reason: .exited))
            }
            let controller = self.controller(launcher: launcher, prober: prober)

            await #expect(throws: PHPFPMControllerError.exitedDuringStartup(status: 1, message: "")) {
                try await controller.start(runtime)
            }
            #expect(controller.state == .failed(.exitedDuringStartup(status: 1, message: "")))
        }
    }

    @Test
    func timesOutWhenTheSocketNeverOpens() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = self.controller(
                launcher: launcher,
                prober: FakeUnixSocketProber(results: [false]),
                readinessTimeout: .milliseconds(120)
            )

            await #expect(throws: PHPFPMControllerError.readinessTimedOut(socketPath: runtime.pool.socketPath)) {
                try await controller.start(runtime)
            }
            #expect(launcher.launches.first?.process.receivedStops.map(\.signal) == [ProcessSignal.quit])
        }
    }

    @Test
    func stopsGracefullyAndRemovesRuntimeFiles() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = self.controller(launcher: launcher, prober: FakeUnixSocketProber(results: [false, true]))
            try await controller.start(runtime)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: URL(filePath: runtime.pool.socketPath))
            try Data().write(to: URL(filePath: runtime.pool.pidPath))

            await controller.stop()

            #expect(controller.state == .stopped)
            #expect(!controller.isRunning)
            #expect(launcher.launches.first?.process.receivedStops.map(\.signal) == [ProcessSignal.quit])
            #expect(!FileManager.default.fileExists(atPath: runtime.pool.socketPath))
            #expect(!FileManager.default.fileExists(atPath: runtime.pool.pidPath))
        }
    }

    @Test
    func reportsAlreadyRunning() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let controller = self.controller(
                launcher: FakeProcessLauncher(),
                prober: FakeUnixSocketProber(results: [false, true])
            )
            try await controller.start(runtime)

            await #expect(throws: PHPFPMControllerError.alreadyRunning) {
                try await controller.start(runtime)
            }
        }
    }

    @Test
    func restartsWithTheCurrentConfiguration() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = self.controller(launcher: launcher, prober: FakeUnixSocketProber(results: [false, true]))
            try await controller.start(runtime)

            try await controller.restart()

            #expect(controller.state == .running(pid: 2))
            #expect(launcher.launches.count == 2)
            #expect(launcher.launches[0].request.arguments == launcher.launches[1].request.arguments)
            #expect(launcher.launches[0].process.receivedStops.map(\.signal) == [ProcessSignal.quit])
        }
    }

    @Test
    func restartWithoutAConfigurationFails() async throws {
        let controller = self.controller(launcher: FakeProcessLauncher(), prober: FakeUnixSocketProber())

        await #expect(throws: PHPFPMControllerError.notRunning) {
            try await controller.restart()
        }
    }

    @Test
    func applyRollsBackToThePreviousConfiguration() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = self.controller(launcher: launcher, prober: FakeUnixSocketProber(results: [false, true]))
            try await controller.start(runtime)

            let invalidPool = PHPFPMPoolConfiguration(
                socketPath: runtime.pool.socketPath,
                documentRootPath: runtime.pool.documentRootPath,
                errorLogPath: runtime.pool.errorLogPath,
                pidPath: runtime.pool.pidPath,
                maxChildren: 0,
                environment: runtime.pool.environment
            )
            let invalid = PHPFPMRuntimeConfiguration(
                executableURL: runtime.executableURL,
                configurationURL: runtime.configurationURL,
                pool: invalidPool
            )

            await #expect(throws: PHPFPMControllerError.self) {
                try await controller.apply(invalid)
            }

            #expect(controller.state == .running(pid: 2))
            #expect(controller.currentRuntime == runtime)
            #expect(launcher.launches.count == 2)
            let config = try String(contentsOf: runtime.configurationURL, encoding: .utf8)
            #expect(config.contains("pm.max_children = 5"))
        }
    }

    @Test
    func applyStartsWhenStopped() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let controller = self.controller(launcher: launcher, prober: FakeUnixSocketProber(results: [false, true]))

            try await controller.apply(runtime)

            #expect(controller.state == .running(pid: 1))
            #expect(controller.currentRuntime == runtime)
        }
    }

    // MARK: - Helpers

    private func controller(
        launcher: FakeProcessLauncher,
        prober: FakeUnixSocketProber,
        inspector: FakePHPFPMProcessInspector = FakePHPFPMProcessInspector(),
        readinessTimeout: Duration = .seconds(10)
    ) -> PHPFPMController {
        PHPFPMController(
            launcher: launcher,
            prober: prober,
            processInspector: inspector,
            timeSource: FakeTimeSource(),
            readinessTimeout: readinessTimeout,
            stopTimeout: .seconds(1)
        )
    }

    private func runtime(in directory: URL) -> PHPFPMRuntimeConfiguration {
        let documentRoot = directory.appending(path: "public", directoryHint: .isDirectory)
        return PHPFPMRuntimeConfiguration(
            executableURL: URL(filePath: "/usr/local/bin/php-fpm"),
            configurationURL: directory.appending(path: "php-fpm.conf"),
            pool: PHPFPMPoolConfiguration(
                socketPath: directory.appending(path: "fpm.sock").path(percentEncoded: false),
                documentRootPath: documentRoot.path(percentEncoded: false),
                errorLogPath: directory.appending(path: "fpm.log").path(percentEncoded: false),
                pidPath: directory.appending(path: "fpm.pid").path(percentEncoded: false),
                environment: ["HOME": "/Users/dev"]
            )
        )
    }
}
