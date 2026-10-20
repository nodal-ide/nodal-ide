import Foundation

enum NginxValidationResult: Equatable, Sendable {
    case valid
    case invalid(message: String)
}

@MainActor
protocol NginxConfigValidating: AnyObject {
    func validate(
        configURL: URL,
        prefix: NginxPrefix,
        executableURL: URL
    ) async -> NginxValidationResult
}

/// Validates a generated nginx configuration with `nginx -t` without touching the running master.
@MainActor
final class NginxConfigValidator: NginxConfigValidating {
    private let launcher: any ProcessLaunching

    init(launcher: (any ProcessLaunching)? = nil) {
        self.launcher = launcher ?? SystemProcessLauncher()
    }

    func validate(
        configURL: URL,
        prefix: NginxPrefix,
        executableURL: URL
    ) async -> NginxValidationResult {
        let request = ProcessLaunchRequest(
            executableURL: executableURL,
            arguments: [
                "-t",
                "-p", prefix.root.path(percentEncoded: false),
                "-c", configURL.path(percentEncoded: false)
            ],
            outputLimit: 200
        )

        do {
            let process = try launcher.launch(request)
            let exit = await process.waitForExit()
            guard exit.isSuccess else {
                return .invalid(message: Self.message(from: process, exit: exit))
            }
            return .valid
        } catch {
            return .invalid(message: error.localizedDescription)
        }
    }

    private static func message(from process: any ManagedProcess, exit: ProcessExit) -> String {
        let output = process.outputTail.map(\.text).filter { !$0.isEmpty }
        guard !output.isEmpty else {
            return "nginx -t failed with status \(exit.status)."
        }
        return output.joined(separator: "\n")
    }
}
