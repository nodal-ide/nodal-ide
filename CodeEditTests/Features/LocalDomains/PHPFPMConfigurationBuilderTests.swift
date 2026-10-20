import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PHPFPMConfigurationBuilderTests {
    @Test
    func emitsAGeneratedPool() throws {
        let config = try PHPFPMConfigurationBuilder.configuration(pool())

        #expect(config.contains("[global]"))
        #expect(config.contains("[www]"))
        #expect(config.contains("listen = /sites/app/fpm.sock"))
        #expect(config.contains("listen.mode = 0600"))
        #expect(config.contains("pm = dynamic"))
        #expect(config.contains("pm.max_children = 5"))
        #expect(config.contains("pm.max_requests = 500"))
        #expect(config.contains("request_terminate_timeout = 60s"))
        #expect(config.contains("chdir = /sites/app/public"))
        #expect(config.contains("catch_workers_output = yes"))
        #expect(config.contains("clear_env = yes"))
        #expect(config.contains("php_admin_flag[opcache.validate_timestamps] = on"))
        #expect(config.contains("php_admin_value[opcache.revalidate_freq] = 0"))
    }

    @Test
    func doesNotLeakTheAppEnvironment() throws {
        let environment = PHPFPMEnvironment.allowlist(
            runtimeBinPath: "/runtimes/php/bin",
            from: [
                "HOME": "/Users/dev",
                "PATH": "/usr/bin:/bin",
                "TMPDIR": "/var/tmp/",
                "AWS_SECRET_ACCESS_KEY": "s3cr3t",
                "GITHUB_TOKEN": "ghp_xxx"
            ]
        )

        #expect(environment["HOME"] == "/Users/dev")
        #expect(environment["TMPDIR"] == "/var/tmp/")
        #expect(environment["PATH"] == "/runtimes/php/bin:/usr/bin:/bin")
        #expect(environment["CE_RUNTIME_PATH"] == "/runtimes/php/bin")
        #expect(environment["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(environment["GITHUB_TOKEN"] == nil)

        let config = try PHPFPMConfigurationBuilder.configuration(pool(environment: environment))
        #expect(!config.contains("AWS_SECRET"))
        #expect(!config.contains("GITHUB_TOKEN"))
        #expect(!config.contains("s3cr3t"))
    }

    @Test
    func escapesEnvironmentValues() throws {
        let config = try PHPFPMConfigurationBuilder.configuration(
            pool(environment: ["LANG": "en_US.\"UTF-8\"\\x"])
        )

        #expect(config.contains("env[LANG] = \"en_US.\\\"UTF-8\\\"\\\\x\""))
    }

    @Test
    func rejectsUnsafePaths() {
        let configuration = pool(socketPath: "/sites/app/fpm\n.sock")

        #expect(throws: PHPFPMConfigurationError.invalidPath("/sites/app/fpm\n.sock")) {
            try PHPFPMConfigurationBuilder.configuration(configuration)
        }
    }

    @Test
    func rejectsInvalidLimitsAndNames() {
        #expect(throws: PHPFPMConfigurationError.self) {
            try PHPFPMConfigurationBuilder.configuration(pool(maxChildren: 0))
        }
        #expect(throws: PHPFPMConfigurationError.self) {
            try PHPFPMConfigurationBuilder.configuration(pool(poolName: "bad name"))
        }
        #expect(throws: PHPFPMConfigurationError.self) {
            try PHPFPMConfigurationBuilder.configuration(pool(environment: ["BAD-KEY": "x"]))
        }
    }

    @Test
    func keepsSpareServersWithinTheChildLimit() throws {
        let config = try PHPFPMConfigurationBuilder.configuration(pool(maxChildren: 1))

        #expect(config.contains("pm.max_children = 1"))
        #expect(config.contains("pm.start_servers = 1"))
        #expect(config.contains("pm.max_spare_servers = 1"))
    }

    @Test
    func generatedConfigurationIsAcceptedByPHPFPM() async throws {
        guard let fpm = Self.locateFPM() else {
            return
        }

        // php-fpm's config loader trips over parentheses in any path, and a Unix socket path is capped
        // at ~104 bytes, so avoid the test helpers' long, function-derived directory names here.
        let directory = URL(filePath: "/tmp/ce-fpm-" + UUID().uuidString.prefix(8), directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let documentRoot = directory.appending(path: "public", directoryHint: .isDirectory)
        let logs = directory.appending(path: "logs", directoryHint: .isDirectory)
        let run = directory.appending(path: "run", directoryHint: .isDirectory)
        for target in [documentRoot, logs, run] {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }

        let config = try PHPFPMConfigurationBuilder.configuration(
            PHPFPMPoolConfiguration(
                socketPath: directory.appending(path: "fpm.sock").path(percentEncoded: false),
                documentRootPath: documentRoot.path(percentEncoded: false),
                errorLogPath: logs.appending(path: "fpm.log").path(percentEncoded: false),
                pidPath: run.appending(path: "fpm.pid").path(percentEncoded: false),
                environment: PHPFPMEnvironment.allowlist(
                    runtimeBinPath: fpm.deletingLastPathComponent().path(percentEncoded: false),
                    from: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
                )
            )
        )
        let configURL = directory.appending(path: "php-fpm.conf")
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        let process = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: fpm,
                arguments: ["-y", configURL.path(percentEncoded: false), "-t"],
                outputLimit: 40
            )
        )
        let exit = await process.waitForExit()
        let output = process.outputTail.map(\.text).joined(separator: "\n")

        #expect(exit.isSuccess, "php-fpm rejected the generated config: \(output)")
    }

    // MARK: - Helpers

    private func pool(
        poolName: String = "www",
        socketPath: String = "/sites/app/fpm.sock",
        maxChildren: Int = 5,
        environment: [String: String] = ["HOME": "/Users/dev"]
    ) -> PHPFPMPoolConfiguration {
        PHPFPMPoolConfiguration(
            poolName: poolName,
            socketPath: socketPath,
            documentRootPath: "/sites/app/public",
            errorLogPath: "/sites/app/fpm.log",
            pidPath: "/sites/app/fpm.pid",
            maxChildren: maxChildren,
            environment: environment
        )
    }

    private static func locateFPM() -> URL? {
        let candidates = [
            "/opt/homebrew/opt/php/sbin/php-fpm",
            "/usr/local/opt/php/sbin/php-fpm"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(filePath: candidate)
        }
        return nil
    }
}
