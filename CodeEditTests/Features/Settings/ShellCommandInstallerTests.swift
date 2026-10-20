@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct ShellCommandInstallerTests {
    @Test
    func wrapperQuotesAppPathAndForwardsArguments() {
        let script = ShellCommandInstaller.wrapperScript(appPath: "/Applications/Code Edit's.app")

        #expect(script.hasPrefix("#!/bin/sh\nAPP='/Applications/Code Edit'\\''s.app'"))
        #expect(script.contains("exec /usr/bin/open -a \"$APP\" -- \"$@\""))
        #expect(script.contains("exec /usr/bin/open -a \"$APP\""))
    }

    @Test
    func installsExecutableWrapper() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appending(path: ShellCommandInstaller.commandName)
        let appPath = "/Applications/CodeEdit.app"

        let result = await ShellCommandInstaller.install(appPath: appPath, at: destination)
        guard case .success = result else {
            Issue.record("Expected installation to succeed: \(result)")
            return
        }

        #expect(ShellCommandInstaller.isInstalled(appPath: appPath, at: destination))
        #expect(!ShellCommandInstaller.isInstalled(appPath: "/Applications/Other.app", at: destination))

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    }

    @Test
    func wrapperScriptHasValidShellSyntax() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appending(path: ShellCommandInstaller.commandName)
        try ShellCommandInstaller.wrapperScript(appPath: "/Applications/CodeEdit.app")
            .write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", scriptURL.path]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    @Test
    func elevatedCommandInstallsEncodedScript() {
        let script = ShellCommandInstaller.wrapperScript(appPath: "/Applications/CodeEdit.app")
        let destination = URL(fileURLWithPath: "/usr/local/bin/codeedit")
        let command = ShellCommandInstaller.elevatedInstallCommand(script: script, destination: destination)

        #expect(command.contains(Data(script.utf8).base64EncodedString()))
        #expect(command.contains("/bin/mkdir -p '/usr/local/bin'"))
        #expect(command.contains("/bin/chmod 755 '/usr/local/bin/codeedit'"))
    }
}
