import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PHPFPMDetectorTests {
    @Test
    func findsTheSiblingFPMAndChecksTheVersion() async throws {
        try await withTempDir { directory in
            let runtime = makeRuntime(in: directory, version: "8.4.12")
            let fpm = runtime.executable(relativePath: "sbin/php-fpm")
            try makeExecutable(at: fpm)
            let shell = Self.shell(version: "PHP 8.4.12 (fpm-fcgi)")

            let status = await PHPFPMDetector(shell: shell).status(for: runtime)

            #expect(status == .available(PHPFPMInstallation(executableURL: fpm, version: "8.4.12")))
        }
    }

    @Test
    func reportsAMissingFPM() async throws {
        try await withTempDir { directory in
            let runtime = makeRuntime(in: directory, version: "8.4.12")

            let status = await PHPFPMDetector(shell: FakeShellRunner()).status(for: runtime)

            #expect(status == .missing)
        }
    }

    @Test
    func reportsAVersionMismatch() async throws {
        try await withTempDir { directory in
            let runtime = makeRuntime(in: directory, version: "8.4.12")
            try makeExecutable(at: runtime.executable(relativePath: "sbin/php-fpm"))
            let shell = Self.shell(version: "PHP 8.3.0 (fpm-fcgi)")

            let status = await PHPFPMDetector(shell: shell).status(for: runtime)

            #expect(status == .versionMismatch(expected: "8.4.12", found: "8.3.0"))
        }
    }

    @Test
    func fallsBackToThePathLookup() async throws {
        try await withTempDir { directory in
            let runtime = makeRuntime(in: directory, version: "8.4.12")
            let onPath = directory.appending(path: "sbin/php-fpm")
            try makeExecutable(at: onPath)
            let shell = Self.shell(version: "PHP 8.4.12 (fpm-fcgi)", whichPath: onPath)

            let status = await PHPFPMDetector(shell: shell).status(for: runtime)

            #expect(status == .available(PHPFPMInstallation(executableURL: onPath, version: "8.4.12")))
        }
    }

    @Test
    func reportsAnUnusableFPM() async throws {
        try await withTempDir { directory in
            let runtime = makeRuntime(in: directory, version: "8.4.12")
            let fpm = runtime.executable(relativePath: "sbin/php-fpm")
            try makeExecutable(at: fpm)
            let shell = Self.shell(version: "not a php binary")

            let status = await PHPFPMDetector(shell: shell).status(for: runtime)

            #expect(status == .unusable(fpm))
        }
    }

    @Test
    func parsesVersionsFromFPMOutput() {
        #expect(PHPFPMDetector.parseVersion(from: "PHP 8.4.12 (fpm-fcgi)") == "8.4.12")
        #expect(PHPFPMDetector.parseVersion(from: "PHP 8.1.2") == "8.1.2")
        #expect(PHPFPMDetector.parseVersion(from: "garbage") == nil)
    }

    @Test
    func comparesMajorAndMinorVersions() {
        #expect(PHPFPMDetector.matches("8.4.12", "8.4.1"))
        #expect(!PHPFPMDetector.matches("8.4.12", "8.3.12"))
        #expect(PHPFPMDetector.matches("8.4", "8.4.12"))
    }

    @Test
    func detectsTheInstalledHomebrewFPMWhenPresent() async throws {
        let root = URL(filePath: "/opt/homebrew/opt/php")
        let fpm = root.appending(path: "sbin/php-fpm")
        let php = root.appending(path: "bin/php")
        guard FileManager.default.isExecutableFile(atPath: fpm.path(percentEncoded: false)),
              FileManager.default.isExecutableFile(atPath: php.path(percentEncoded: false)) else {
            return
        }

        let shell = SystemShellRunner()
        let versionResult = await shell.run("\(php.path(percentEncoded: false)) -r 'echo PHP_VERSION;'")
        let version = versionResult.output.split(separator: "\n").last.map(String.init) ?? ""
        guard !version.isEmpty else {
            return
        }

        let runtime = InstalledRuntime(
            kind: .php,
            version: version,
            source: .brew,
            executableDirectory: php.deletingLastPathComponent()
        )
        let status = await PHPFPMDetector(shell: shell).status(for: runtime)

        #expect(status == .available(PHPFPMInstallation(executableURL: fpm, version: version)))
    }

    // MARK: - Helpers

    private func makeRuntime(in directory: URL, version: String) -> InstalledRuntime {
        InstalledRuntime(
            kind: .php,
            version: version,
            source: .brew,
            executableDirectory: directory.appending(path: "bin", directoryHint: .isDirectory)
        )
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private static func shell(version: String, whichPath: URL? = nil) -> FakeShellRunner {
        let shell = FakeShellRunner()
        let path = whichPath?.path(percentEncoded: false)
        shell.handler = { command in
            if command.hasSuffix(" -v") {
                return ShellResult(output: version, status: 0)
            }
            if command == "command -v php-fpm", let path {
                return ShellResult(output: path, status: 0)
            }
            return ShellResult(output: "", status: 1)
        }
        return shell
    }
}
