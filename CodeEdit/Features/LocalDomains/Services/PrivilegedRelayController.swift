import Foundation

enum PrivilegedRelayError: Error, Equatable, LocalizedError {
    case helperMissing(String)
    case launchFailed(String)
    case exitedDuringStartup(String)
    case readinessTimedOut

    var errorDescription: String? {
        switch self {
        case .helperMissing(let path):
            return "The portless relay is missing from the app bundle at \(path)."
        case .launchFailed(let message):
            return "Could not start the portless relay: \(message)"
        case .exitedDuringStartup(let message):
            return "The portless relay exited during startup. \(message)"
        case .readinessTimedOut:
            return "The portless relay did not start listening on ports 80 and 443 in time."
        }
    }
}

@MainActor
protocol RelayStarting: AnyObject {
    var isRunning: Bool { get }
    func start() async throws
    func stop() async
}

/// Starts the embedded loopback relay that owns 80/443 and forwards to nginx on 8080/8443.
///
/// The helper only opens listeners and forwards TCP to loopback; it never reads project files. It is
/// launched directly (without elevation) so it runs with the user's privileges. macOS releases that
/// require administrator rights for low ports surface a clear launch failure instead of silently
/// serving on the wrong port.
@MainActor
final class PrivilegedRelayController: RelayStarting {
    private let launcher: any ProcessLaunching
    private let helperURL: URL
    private let readinessTimeout: Duration
    private var process: (any ManagedProcess)?

    init(
        launcher: (any ProcessLaunching)? = nil,
        helperURL: URL? = nil,
        readinessTimeout: Duration = .seconds(3)
    ) {
        self.launcher = launcher ?? SystemProcessLauncher()
        self.helperURL = helperURL ?? Bundle.main.bundleURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: "CodeEditRelay")
        self.readinessTimeout = readinessTimeout
    }

    var isRunning: Bool {
        guard let process else {
            return false
        }
        return process.isRunning && process.exit == nil
    }

    func start() async throws {
        if isRunning {
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path(percentEncoded: false)) else {
            throw PrivilegedRelayError.helperMissing(helperURL.path(percentEncoded: false))
        }

        let started: any ManagedProcess
        do {
            started = try launcher.launch(
                ProcessLaunchRequest(
                    executableURL: helperURL,
                    arguments: [],
                    workingDirectory: nil,
                    outputLimit: 50
                )
            )
        } catch {
            throw PrivilegedRelayError.launchFailed(error.localizedDescription)
        }
        process = started

        let deadline = Date().addingTimeInterval(readinessTimeout.timeInterval)
        while true {
            if let exit = started.exit {
                process = nil
                throw PrivilegedRelayError.exitedDuringStartup(tail(of: started, status: exit.status))
            }
            if started.outputTail.contains(where: { $0.text.contains("CodeEditRelay: ready") }) {
                return
            }
            if Date() >= deadline {
                await started.stop(signal: ProcessSignal.terminate, timeout: .seconds(2))
                process = nil
                throw PrivilegedRelayError.readinessTimedOut
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func stop() async {
        guard let process else {
            return
        }
        await process.stop(signal: ProcessSignal.terminate, timeout: .seconds(2))
        self.process = nil
    }

    private func tail(of process: any ManagedProcess, status: Int32) -> String {
        let output = process.outputTail.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        return output.isEmpty ? "Exit status \(status)." : output
    }
}
