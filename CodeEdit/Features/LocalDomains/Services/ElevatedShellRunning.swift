import Foundation

/// Runs a single shell command with administrator privileges through `osascript`'s
/// `do shell script … with administrator privileges`, mirroring `ShellCommandInstaller`.
/// A cancelled authorization comes back as a non-zero result rather than an error.
@MainActor
protocol ElevatedShellRunning: AnyObject {
    func run(_ command: String) async -> ShellResult
}

@MainActor
final class AppleScriptElevatedShellRunner: ElevatedShellRunning {
    private let launcher: any ProcessLaunching

    init(launcher: (any ProcessLaunching)? = nil) {
        self.launcher = launcher ?? SystemProcessLauncher()
    }

    func run(_ command: String) async -> ShellResult {
        let script = "do shell script \(Self.appleScriptLiteral(command)) with administrator privileges"
        do {
            let process = try launcher.launch(
                ProcessLaunchRequest(
                    executableURL: URL(filePath: "/usr/bin/osascript"),
                    arguments: ["-e", script],
                    environment: nil,
                    workingDirectory: nil,
                    outputLimit: 200
                )
            )
            let exit = await process.waitForExit()
            let output = process.outputTail.map(\.text).joined(separator: "\n")
            return ShellResult(output: output, status: exit.status)
        } catch {
            return ShellResult(output: "\(error)", status: -1)
        }
    }

    /// Escapes a value for use inside an AppleScript double-quoted string literal.
    static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
