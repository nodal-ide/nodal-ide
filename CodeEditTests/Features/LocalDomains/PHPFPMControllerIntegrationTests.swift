import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PHPFPMControllerIntegrationTests {
    @Test
    func startsServesAndStopsARealPHPFPM() async throws {
        guard let fpm = Self.locateFPM() else {
            return
        }

        // A Unix socket path is capped at ~104 bytes and php-fpm's config loader trips over
        // parentheses, so use a short, simple temp directory here.
        let directory = URL(filePath: "/tmp/ce-fpm-ctl-" + UUID().uuidString.prefix(8), directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let documentRoot = directory.appending(path: "public", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
        try "<?php echo 'ok';".write(
            to: documentRoot.appending(path: "index.php"),
            atomically: true,
            encoding: .utf8
        )

        let socketPath = directory.appending(path: "fpm.sock").path(percentEncoded: false)
        let pidPath = directory.appending(path: "fpm.pid").path(percentEncoded: false)
        let runtime = PHPFPMRuntimeConfiguration(
            executableURL: fpm,
            configurationURL: directory.appending(path: "php-fpm.conf"),
            pool: PHPFPMPoolConfiguration(
                socketPath: socketPath,
                documentRootPath: documentRoot.path(percentEncoded: false),
                errorLogPath: directory.appending(path: "fpm.log").path(percentEncoded: false),
                pidPath: pidPath,
                environment: PHPFPMEnvironment.allowlist(
                    runtimeBinPath: fpm.deletingLastPathComponent().path(percentEncoded: false),
                    from: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
                )
            )
        )

        let controller = PHPFPMController(launcher: SystemProcessLauncher(), prober: UnixSocketProbe())
        do {
            try await controller.start(runtime)
        } catch {
            await controller.stop()
            throw error
        }

        let pid = try #require(controller.pid)
        #expect(controller.isRunning)
        #expect(controller.state == .running(pid: pid))
        #expect(await UnixSocketProbe().isConnectable(path: socketPath, timeout: .seconds(1)))
        #expect(FileManager.default.fileExists(atPath: pidPath))

        await controller.stop()

        #expect(controller.state == .stopped)
        #expect(!controller.isRunning)
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        #expect(!FileManager.default.fileExists(atPath: pidPath))
        #expect(kill(pid, 0) != 0)
    }

    private static func locateFPM() -> URL? {
        for candidate in ["/opt/homebrew/opt/php/sbin/php-fpm", "/usr/local/opt/php/sbin/php-fpm"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(filePath: candidate)
        }
        return nil
    }
}
