import Foundation

struct ShellResult: Equatable, Sendable {
    let output: String
    let status: Int32

    var succeeded: Bool {
        status == 0
    }
}

/// Minimal shell abstraction for tool discovery so callers can be tested without spawning processes.
protocol ShellRunning: Sendable {
    func run(_ command: String) async -> ShellResult
}

struct SystemShellRunner: ShellRunning {
    func run(_ command: String) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let result = RuntimeShell.runResult(command)
                continuation.resume(returning: ShellResult(output: result.output, status: result.status))
            }
        }
    }
}
