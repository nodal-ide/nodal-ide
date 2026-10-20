import Darwin
import Foundation

enum ProxyStateResetError: Error, Equatable, LocalizedError {
    case processNotOwned(pid: Int32)
    case processNotNginx(pid: Int32)
    case processStillRunning(pid: Int32)
    case removalFailed(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case .processNotOwned(let pid):
            return "A process owned by another user (\(pid)) is using the local proxy."
        case .processNotNginx(let pid):
            return "The process in the local proxy PID file (\(pid)) is not nginx."
        case .processStillRunning(let pid):
            return "nginx (\(pid)) did not stop, so generated state was left in place."
        case .removalFailed(let path, _):
            return "Could not remove \(path)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .processNotOwned, .processNotNginx:
            return "Stop the process manually, then try again."
        case .processStillRunning:
            return "Quit CodeEdit, stop nginx from Activity Monitor, then try again."
        case .removalFailed(_, let message):
            return message
        }
    }
}

@MainActor
protocol ProxyProcessStopping {
    func stopIfRunning(pidURL: URL) async throws
}

/// Stops an nginx master referenced by a PID file, but only after verifying that the process is owned
/// by the current user and is actually nginx. Never signals a foreign process.
@MainActor
final class NginxPidFileStopper: ProxyProcessStopping {
    private struct ProcessIdentity: Equatable {
        let uid: UInt32
        let executableName: String
    }

    private let shell: any ShellRunning
    private let timeSource: any TimeSource
    private let currentUID: UInt32

    init(
        shell: any ShellRunning = SystemShellRunner(),
        timeSource: any TimeSource = SystemTimeSource(),
        currentUID: UInt32 = getuid()
    ) {
        self.shell = shell
        self.timeSource = timeSource
        self.currentUID = currentUID
    }

    func stopIfRunning(pidURL: URL) async throws {
        guard let pid = Self.readPID(at: pidURL) else {
            return
        }
        guard let identity = await identity(of: pid) else {
            return
        }
        guard identity.uid == currentUID else {
            throw ProxyStateResetError.processNotOwned(pid: pid)
        }
        guard identity.executableName == "nginx" else {
            throw ProxyStateResetError.processNotNginx(pid: pid)
        }

        _ = await shell.run("kill -QUIT \(pid)")
        if await waitForExit(pid: pid, attempts: 40) {
            return
        }

        _ = await shell.run("kill -KILL \(pid)")
        if await waitForExit(pid: pid, attempts: 10) {
            return
        }
        throw ProxyStateResetError.processStillRunning(pid: pid)
    }

    private func identity(of pid: Int32) async -> ProcessIdentity? {
        let result = await shell.run("ps -o uid= -o comm= -p \(pid)")
        guard result.succeeded else {
            return nil
        }
        let fields = result.output.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard fields.count == 2, let uid = UInt32(fields[0]) else {
            return nil
        }
        let command = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessIdentity(uid: uid, executableName: URL(filePath: command).lastPathComponent)
    }

    private func waitForExit(pid: Int32, attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if !(await isAlive(pid: pid)) {
                return true
            }
            try? await timeSource.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func isAlive(pid: Int32) async -> Bool {
        let result = await shell.run("kill -0 \(pid)")
        return result.succeeded
    }

    private static func readPID(at url: URL) -> Int32? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
