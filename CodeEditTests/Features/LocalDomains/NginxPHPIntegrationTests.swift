import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxPHPIntegrationTests {
    @Test
    func servesPHPThroughNginxAndRoutesFrontController() async throws {
        guard let nginx = await SystemNginxLocator().locate(), let fpm = Self.locateFPM() else {
            return
        }

        let directory = URL(filePath: "/tmp/ce-php-" + UUID().uuidString.prefix(8), directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let outcome = try await Self.run(nginx: nginx, fpm: fpm, directory: directory)

        #expect(outcome.index == "index:/")
        #expect(outcome.info.contains("uri=/info.php/extra/path?x=1"))
        #expect(outcome.info.contains("script=/info.php"))
        #expect(outcome.info.contains("path=/extra/path"))
        #expect(outcome.info.contains("file=info.php"))
        #expect(outcome.routed == "index:/some/missing/path")
        #expect(outcome.statuses == ["404", "404", "404"])
        #expect(!outcome.nginxRunning)
        #expect(!outcome.fpmRunning)
    }

    // MARK: - Scenario

    private static let directoryPort = 18146
    private static let routerPort = 18147

    private struct Outcome {
        let index: String
        let info: String
        let routed: String
        let statuses: [String]
        let nginxRunning: Bool
        let fpmRunning: Bool
    }

    private struct SiteSpec {
        let name: String
        let port: Int
        let documentRoot: URL
        let socketPath: String
        let routing: LocalSiteRouting
    }

    private static func run(nginx: NginxInstallation, fpm: URL, directory: URL) async throws -> Outcome {
        let documentRoot = directory.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
        try writeFixtures(to: documentRoot)

        let socketPath = directory.appending(path: "fpm.sock").path(percentEncoded: false)
        let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
        try prefix.createDirectories()
        let runtime = makeRuntime(directory: directory, documentRoot: documentRoot, socketPath: socketPath, fpm: fpm)
        let fpmController = PHPFPMController(launcher: SystemProcessLauncher(), prober: UnixSocketProbe())
        let nginxController = NginxController(prefix: prefix)

        do {
            try await fpmController.start(runtime)
            try await nginxController.apply(
                executableURL: nginx.executableURL,
                sites: sites(documentRoot: documentRoot, socketPath: socketPath, prefix: prefix),
                listenPorts: [directoryPort, routerPort]
            )
            let responses = try await collectResponses()
            await nginxController.stop()
            await fpmController.stop()
            return Outcome(
                index: responses.index,
                info: responses.info,
                routed: responses.routed,
                statuses: responses.statuses,
                nginxRunning: nginxController.isRunning,
                fpmRunning: fpmController.isRunning
            )
        } catch {
            await nginxController.stop()
            await fpmController.stop()
            throw error
        }
    }

    private struct Responses {
        let index: String
        let info: String
        let routed: String
        let statuses: [String]
    }

    private static func sites(
        documentRoot: URL,
        socketPath: String,
        prefix: NginxPrefix
    ) -> [NginxSiteConfiguration] {
        [
            site(
                SiteSpec(
                    name: "directory.localhost",
                    port: directoryPort,
                    documentRoot: documentRoot,
                    socketPath: socketPath,
                    routing: .directory
                ),
                prefix: prefix
            ),
            site(
                SiteSpec(
                    name: "router.localhost",
                    port: routerPort,
                    documentRoot: documentRoot,
                    socketPath: socketPath,
                    routing: .frontController
                ),
                prefix: prefix
            )
        ]
    }

    private static func collectResponses() async throws -> Responses {
        let index = try await fetch(host: "directory.localhost", port: directoryPort, path: "/")
        let info = try await fetch(
            host: "directory.localhost",
            port: directoryPort,
            path: "/info.php/extra/path?x=1"
        )
        let routed = try await fetch(host: "router.localhost", port: routerPort, path: "/some/missing/path")
        let statuses = [
            try await status(host: "directory.localhost", port: directoryPort, path: "/missing.php"),
            try await status(host: "directory.localhost", port: directoryPort, path: "/nope"),
            try await status(host: "router.localhost", port: routerPort, path: "/missing.php")
        ]
        return Responses(index: index, info: info, routed: routed, statuses: statuses)
    }

    // MARK: - Fixtures

    private static func writeFixtures(to root: URL) throws {
        let index = """
        <?php
        header('Content-Type: text/plain');
        echo 'index:' . $_SERVER['REQUEST_URI'];
        """
        let info = """
        <?php
        header('Content-Type: text/plain');
        echo 'uri=' . $_SERVER['REQUEST_URI']
            . ';script=' . $_SERVER['SCRIPT_NAME']
            . ';path=' . ($_SERVER['PATH_INFO'] ?? '')
            . ';file=' . basename($_SERVER['SCRIPT_FILENAME']);
        """
        try index.write(to: root.appending(path: "index.php"), atomically: true, encoding: .utf8)
        try info.write(to: root.appending(path: "info.php"), atomically: true, encoding: .utf8)
    }

    private static func makeRuntime(
        directory: URL,
        documentRoot: URL,
        socketPath: String,
        fpm: URL
    ) -> PHPFPMRuntimeConfiguration {
        PHPFPMRuntimeConfiguration(
            executableURL: fpm,
            configurationURL: directory.appending(path: "php-fpm.conf"),
            pool: PHPFPMPoolConfiguration(
                socketPath: socketPath,
                documentRootPath: documentRoot.path(percentEncoded: false),
                errorLogPath: directory.appending(path: "fpm.log").path(percentEncoded: false),
                pidPath: directory.appending(path: "fpm.pid").path(percentEncoded: false),
                environment: PHPFPMEnvironment.allowlist(
                    runtimeBinPath: fpm.deletingLastPathComponent().path(percentEncoded: false),
                    from: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
                )
            )
        )
    }

    private static func site(_ spec: SiteSpec, prefix: NginxPrefix) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: spec.name,
            listenPort: spec.port,
            documentRootPath: spec.documentRoot.path(percentEncoded: false),
            upstream: .phpFPM(socketPath: spec.socketPath),
            routing: spec.routing,
            entryFile: "index.php",
            accessLogPath: prefix.logsDirectory.appending(path: "\(spec.name).access.log").path(percentEncoded: false),
            errorLogPath: prefix.errorLogURL.path(percentEncoded: false)
        )
    }

    // MARK: - HTTP

    private static func fetch(host: String, port: Int, path: String) async throws -> String {
        guard let body = try await runCurl([
            "-sS", "--fail", "-H", "Host: \(host)", "http://127.0.0.1:\(port)\(path)"
        ]) else {
            throw FetchError.curlFailed
        }
        return body
    }

    private static func status(host: String, port: Int, path: String) async throws -> String {
        guard let code = try await runCurl([
            "-sS", "-o", "/dev/null", "-w", "%{http_code}",
            "-H", "Host: \(host)", "http://127.0.0.1:\(port)\(path)"
        ]) else {
            throw FetchError.curlFailed
        }
        return code
    }

    private static func runCurl(_ arguments: [String]) async throws -> String? {
        let process = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/curl"),
                arguments: arguments,
                outputLimit: 20
            )
        )
        let exit = await process.waitForExit()
        guard exit.isSuccess else {
            return nil
        }
        return process.outputTail.map(\.text).joined(separator: "\n")
    }

    private static func locateFPM() -> URL? {
        for candidate in ["/opt/homebrew/opt/php/sbin/php-fpm", "/usr/local/opt/php/sbin/php-fpm"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(filePath: candidate)
        }
        return nil
    }

    private enum FetchError: Error {
        case curlFailed
    }
}
