import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct SystemNginxLocatorTests {
    private func makeExecutable(in directory: URL, named name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }

    @Test
    func inspectsExecutableVersionAndPrefix() async throws {
        try await withTempDir { directory in
            let executable = try makeExecutable(in: directory, named: "nginx")

            let shell = FakeShellRunner()
            shell.handler = { command in
                if command.hasSuffix(" -v") {
                    return ShellResult(output: "nginx version: nginx/1.29.4", status: 0)
                }
                if command.hasSuffix(" -V") {
                    return ShellResult(output: "configure arguments: --prefix=/opt/homebrew/var/www", status: 0)
                }
                return ShellResult(output: "", status: 1)
            }

            let locator = SystemNginxLocator(shell: shell)
            let installation = await locator.inspect(executable)

            #expect(installation?.version == "1.29.4")
            #expect(installation?.prefixURL == URL(filePath: "/opt/homebrew/var/www"))
            #expect(installation?.executableURL == executable)
        }
    }

    @Test
    func inspectRejectsMissingExecutable() async throws {
        try await withTempDir { directory in
            let locator = SystemNginxLocator(shell: FakeShellRunner())

            let installation = await locator.inspect(directory.appending(path: "nginx"))

            #expect(installation == nil)
        }
    }

    @Test
    func inspectRejectsNonExecutableFile() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "nginx")
            try Data("not executable".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path(percentEncoded: false)
            )

            let locator = SystemNginxLocator(shell: FakeShellRunner())
            let installation = await locator.inspect(url)

            #expect(installation == nil)
        }
    }

    @Test
    func inspectReturnsNilWhenVersionCommandFails() async throws {
        try await withTempDir { directory in
            let executable = try makeExecutable(in: directory, named: "nginx")

            let shell = FakeShellRunner()
            shell.setDefault(ShellResult(output: "boom", status: 1))

            let locator = SystemNginxLocator(shell: shell)
            let installation = await locator.inspect(executable)

            #expect(installation == nil)
        }
    }
}
