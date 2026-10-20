import Darwin
import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PHPFPMControllerOrphanTests {
    @Test
    func reapsAnOrphanedProcessThatOwnsTheSiteSocket() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: URL(filePath: runtime.pool.socketPath))
            try Data("42".utf8).write(to: URL(filePath: runtime.pool.pidPath))

            let inspector = FakePHPFPMProcessInspector()
            inspector.setRunning(
                42,
                executable: runtime.executableURL.path(percentEncoded: false),
                arguments: [
                    "php-fpm: master process (\(runtime.configurationURL.path(percentEncoded: false)))"
                ]
            )
            let launcher = FakeProcessLauncher()
            let controller = self.controller(
                launcher: launcher,
                prober: FakeUnixSocketProber(results: [false, true]),
                inspector: inspector
            )

            try await controller.start(runtime)

            #expect(inspector.signals == [SIGQUIT])
            #expect(controller.state == .running(pid: 1))
            #expect(!FileManager.default.fileExists(atPath: runtime.pool.pidPath))
            #expect(launcher.launches.count == 1)
        }
    }

    @Test
    func refusesToReapAProcessWithADifferentConfig() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: URL(filePath: runtime.pool.socketPath))
            try Data("42".utf8).write(to: URL(filePath: runtime.pool.pidPath))

            let inspector = FakePHPFPMProcessInspector()
            inspector.setRunning(
                42,
                executable: runtime.executableURL.path(percentEncoded: false),
                arguments: ["php-fpm: master process (/tmp/other-site.conf)"]
            )
            let launcher = FakeProcessLauncher()
            let controller = self.controller(
                launcher: launcher,
                prober: FakeUnixSocketProber(results: [true]),
                inspector: inspector
            )

            await #expect(throws: PHPFPMControllerError.socketInUse(runtime.pool.socketPath)) {
                try await controller.start(runtime)
            }

            #expect(inspector.signals.isEmpty)
            #expect(launcher.launches.isEmpty)
            #expect(FileManager.default.fileExists(atPath: runtime.pool.pidPath))
        }
    }

    @Test
    func forceKillsAnOrphanThatIgnoresQuit() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: URL(filePath: runtime.pool.socketPath))
            try Data("42".utf8).write(to: URL(filePath: runtime.pool.pidPath))

            let inspector = FakePHPFPMProcessInspector()
            inspector.ignoresQuit = true
            inspector.setRunning(
                42,
                executable: runtime.executableURL.path(percentEncoded: false),
                arguments: [
                    "php-fpm: master process (\(runtime.configurationURL.path(percentEncoded: false)))"
                ]
            )
            let controller = self.controller(
                launcher: FakeProcessLauncher(),
                prober: FakeUnixSocketProber(results: [false, true]),
                inspector: inspector
            )

            try await controller.start(runtime)

            #expect(inspector.signals == [SIGQUIT, SIGKILL])
            #expect(controller.state == .running(pid: 1))
        }
    }

    @Test
    func removesRuntimeFilesWhenTheLaunchFails() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            try FileManager.default.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("42".utf8).write(to: URL(filePath: runtime.pool.socketPath))
            try Data("42".utf8).write(to: URL(filePath: runtime.pool.pidPath))

            let launcher = FakeProcessLauncher()
            launcher.launchError = NSError(domain: "test", code: 1)
            let controller = self.controller(
                launcher: launcher,
                prober: FakeUnixSocketProber(results: [false]),
                inspector: FakePHPFPMProcessInspector()
            )

            await #expect(throws: PHPFPMControllerError.self) {
                try await controller.start(runtime)
            }

            #expect(!FileManager.default.fileExists(atPath: runtime.pool.socketPath))
            #expect(!FileManager.default.fileExists(atPath: runtime.pool.pidPath))
        }
    }

    @Test
    func cleansUpRuntimeFilesAfterAReadinessTimeout() async throws {
        try await withTempDir { directory in
            let runtime = self.runtime(in: directory)
            let launcher = FakeProcessLauncher()
            let prober = FakeUnixSocketProber(results: [false])
            prober.onProbe = { _ in
                try? Data().write(to: URL(filePath: runtime.pool.socketPath))
                try? Data("0".utf8).write(to: URL(filePath: runtime.pool.pidPath))
            }
            let controller = self.controller(
                launcher: launcher,
                prober: prober,
                inspector: FakePHPFPMProcessInspector(),
                readinessTimeout: .milliseconds(120)
            )

            await #expect(throws: PHPFPMControllerError.readinessTimedOut(socketPath: runtime.pool.socketPath)) {
                try await controller.start(runtime)
            }

            #expect(!FileManager.default.fileExists(atPath: runtime.pool.socketPath))
            #expect(!FileManager.default.fileExists(atPath: runtime.pool.pidPath))
        }
    }

    // MARK: - Helpers

    private func controller(
        launcher: FakeProcessLauncher,
        prober: FakeUnixSocketProber,
        inspector: FakePHPFPMProcessInspector,
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
        PHPFPMRuntimeConfiguration(
            executableURL: URL(filePath: "/usr/local/bin/php-fpm"),
            configurationURL: directory.appending(path: "php-fpm.conf"),
            pool: PHPFPMPoolConfiguration(
                socketPath: directory.appending(path: "fpm.sock").path(percentEncoded: false),
                documentRootPath: directory.appending(path: "public").path(percentEncoded: false),
                errorLogPath: directory.appending(path: "fpm.log").path(percentEncoded: false),
                pidPath: directory.appending(path: "fpm.pid").path(percentEncoded: false),
                environment: ["HOME": "/Users/dev"]
            )
        )
    }
}
