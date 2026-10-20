import Foundation

enum PHPFPMControllerError: Error, Equatable, LocalizedError {
    case alreadyRunning
    case notRunning
    case socketInUse(String)
    case configurationWriteFailed(message: String)
    case launchFailed(message: String)
    case exitedDuringStartup(status: Int32, message: String)
    case readinessTimedOut(socketPath: String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "PHP-FPM is already running."
        case .notRunning:
            return "PHP-FPM is not running."
        case .socketInUse(let path):
            return "Another PHP-FPM is already listening on \(path)."
        case .configurationWriteFailed(let message):
            return "Could not write the PHP-FPM configuration: \(message)"
        case .launchFailed(let message):
            return "Could not start PHP-FPM: \(message)"
        case let .exitedDuringStartup(status, message):
            let detail = message.isEmpty ? "" : " \(message)"
            return "PHP-FPM exited during startup with status \(status).\(detail)"
        case .readinessTimedOut(let socketPath):
            return "PHP-FPM did not start accepting connections on \(socketPath) in time."
        }
    }
}

enum PHPFPMControllerState: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case stopping
    case failed(PHPFPMControllerError)
}

/// Everything one site's php-fpm process needs: the executable, where its pool config is written, and
/// the pool itself (socket, limits, logs, environment).
struct PHPFPMRuntimeConfiguration: Equatable, Sendable {
    let executableURL: URL
    let configurationURL: URL
    let pool: PHPFPMPoolConfiguration
}

/// Owns one app-managed php-fpm master for a site: writes the pool config, launches it in the
/// foreground, waits for its Unix socket to accept connections, and stops it gracefully. Never clobbers
/// a socket another process is already serving.
@MainActor
final class PHPFPMController {
    private let launcher: any ProcessLaunching
    private let prober: any UnixSocketProbing
    private let processInspector: any PHPFPMProcessInspecting
    private let timeSource: TimeSource
    private let fileManager: FileManager
    private let readinessTimeout: Duration
    private let stopTimeout: Duration
    private let probeTimeout = Duration.milliseconds(250)

    private var process: (any ManagedProcess)?
    private(set) var currentRuntime: PHPFPMRuntimeConfiguration?
    private(set) var state: PHPFPMControllerState = .stopped

    init(
        launcher: (any ProcessLaunching)? = nil,
        prober: any UnixSocketProbing = UnixSocketProbe(),
        processInspector: any PHPFPMProcessInspecting = SystemPHPFPMProcessInspector(),
        timeSource: TimeSource = SystemTimeSource(),
        fileManager: FileManager = .default,
        readinessTimeout: Duration = .seconds(10),
        stopTimeout: Duration = .seconds(5)
    ) {
        self.launcher = launcher ?? SystemProcessLauncher()
        self.prober = prober
        self.processInspector = processInspector
        self.timeSource = timeSource
        self.fileManager = fileManager
        self.readinessTimeout = readinessTimeout
        self.stopTimeout = stopTimeout
    }

    var isRunning: Bool {
        guard let process else {
            return false
        }
        return process.isRunning && process.exit == nil
    }

    var pid: Int32? {
        process?.pid
    }

    var outputTail: [ProcessOutputLine] {
        process?.outputTail ?? []
    }

    func start(_ runtime: PHPFPMRuntimeConfiguration) async throws {
        if isRunning {
            throw PHPFPMControllerError.alreadyRunning
        }
        try await begin(runtime)
    }

    func stop() async {
        if let process {
            state = .stopping
            await process.stop(signal: ProcessSignal.quit, timeout: stopTimeout)
        }
        self.process = nil
        removeRuntimeFiles()
        state = .stopped
    }

    func restart() async throws {
        guard let runtime = currentRuntime else {
            throw PHPFPMControllerError.notRunning
        }
        await stop()
        try await begin(runtime)
    }

    /// Publishes a new pool configuration and (re)starts the process. If the restart fails, the previous
    /// configuration is restored and started again, so a bad edit never leaves the site down.
    func apply(_ runtime: PHPFPMRuntimeConfiguration) async throws {
        let previous = currentRuntime
        if isRunning {
            await stop()
        }
        do {
            try await begin(runtime)
        } catch {
            if let previous {
                try? await begin(previous)
            }
            throw error
        }
    }

    // MARK: - Lifecycle

    private func begin(_ runtime: PHPFPMRuntimeConfiguration) async throws {
        process = nil
        state = .starting

        try writeConfiguration(runtime)
        try await prepareSocket(runtime)
        try await launch(runtime)
    }

    private func launch(_ runtime: PHPFPMRuntimeConfiguration) async throws {
        let request = ProcessLaunchRequest(
            executableURL: runtime.executableURL,
            arguments: [
                "-F",
                "-y", runtime.configurationURL.path(percentEncoded: false)
            ],
            workingDirectory: runtime.configurationURL.deletingLastPathComponent(),
            outputLimit: 200
        )

        let process: any ManagedProcess
        do {
            process = try launcher.launch(request)
        } catch {
            removeRuntimeFiles(for: runtime)
            let failure = PHPFPMControllerError.launchFailed(message: error.localizedDescription)
            state = .failed(failure)
            throw failure
        }
        self.process = process

        if await waitUntilReady(process: process, socketPath: runtime.pool.socketPath) {
            currentRuntime = runtime
            state = .running(pid: process.pid)
            return
        }

        await process.stop(signal: ProcessSignal.quit, timeout: stopTimeout)
        self.process = nil
        removeRuntimeFiles(for: runtime)

        if let exit = process.exit, !exit.isSuccess {
            let failure = PHPFPMControllerError.exitedDuringStartup(
                status: exit.status,
                message: tail(of: process)
            )
            state = .failed(failure)
            throw failure
        }

        let failure = PHPFPMControllerError.readinessTimedOut(socketPath: runtime.pool.socketPath)
        state = .failed(failure)
        throw failure
    }

    // MARK: - Configuration

    private func writeConfiguration(_ runtime: PHPFPMRuntimeConfiguration) throws {
        do {
            let contents = try PHPFPMConfigurationBuilder.configuration(runtime.pool)
            try fileManager.createDirectory(
                at: runtime.configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try contents.write(to: runtime.configurationURL, atomically: true, encoding: .utf8)
        } catch {
            let failure = PHPFPMControllerError.configurationWriteFailed(message: error.localizedDescription)
            state = .failed(failure)
            throw failure
        }
    }

    /// Reaps a php-fpm left behind by a crashed or force-quit app session before deciding whether a
    /// socket belongs to a foreign process. A pid file alone is not trusted: the process must still be
    /// alive, run the configured php-fpm executable, and reference this site's config file.
    private func prepareSocket(_ runtime: PHPFPMRuntimeConfiguration) async throws {
        let socketPath = runtime.pool.socketPath
        let pidPath = runtime.pool.pidPath

        if let pid = readPid(at: pidPath) {
            if isOurs(pid: pid, runtime: runtime) {
                await terminateOrphan(pid: pid)
                guard !processInspector.isRunning(pid: pid) else {
                    let failure = PHPFPMControllerError.socketInUse(socketPath)
                    state = .failed(failure)
                    throw failure
                }
                try? fileManager.removeItem(atPath: socketPath)
                try? fileManager.removeItem(atPath: pidPath)
            } else if !processInspector.isRunning(pid: pid) {
                try? fileManager.removeItem(atPath: pidPath)
            }
        }

        guard fileManager.fileExists(atPath: socketPath) else {
            return
        }
        if await prober.isConnectable(path: socketPath, timeout: probeTimeout) {
            let failure = PHPFPMControllerError.socketInUse(socketPath)
            state = .failed(failure)
            throw failure
        }
        try? fileManager.removeItem(atPath: socketPath)
    }

    private func readPid(at path: String) -> Int32? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isOurs(pid: Int32, runtime: PHPFPMRuntimeConfiguration) -> Bool {
        guard processInspector.isRunning(pid: pid) else {
            return false
        }
        let expectedExecutable = runtime.executableURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let executable = processInspector.executablePath(pid: pid),
              URL(filePath: executable).resolvingSymlinksInPath().path(percentEncoded: false)
                == expectedExecutable else {
            return false
        }
        let configPath = runtime.configurationURL.path(percentEncoded: false)
        return processInspector.arguments(pid: pid)?.joined(separator: " ").contains(configPath) == true
    }

    private func terminateOrphan(pid: Int32) async {
        _ = processInspector.signal(SIGQUIT, to: pid)
        if await waitUntilStopped(pid: pid) {
            return
        }
        _ = processInspector.signal(SIGKILL, to: pid)
        _ = await waitUntilStopped(pid: pid)
    }

    private func waitUntilStopped(pid: Int32) async -> Bool {
        let deadline = timeSource.now.addingTimeInterval(stopTimeout.timeInterval)
        while processInspector.isRunning(pid: pid) {
            if Task.isCancelled || timeSource.now >= deadline {
                return false
            }
            try? await timeSource.sleep(for: .milliseconds(50))
        }
        return true
    }

    private func removeRuntimeFiles() {
        guard let runtime = currentRuntime else {
            return
        }
        removeRuntimeFiles(for: runtime)
    }

    private func removeRuntimeFiles(for runtime: PHPFPMRuntimeConfiguration) {
        try? fileManager.removeItem(atPath: runtime.pool.socketPath)
        try? fileManager.removeItem(atPath: runtime.pool.pidPath)
    }

    // MARK: - Readiness

    private func waitUntilReady(process: any ManagedProcess, socketPath: String) async -> Bool {
        let deadline = timeSource.now.addingTimeInterval(readinessTimeout.timeInterval)
        while true {
            if await prober.isConnectable(path: socketPath, timeout: probeTimeout) {
                return true
            }
            if process.exit != nil || Task.isCancelled || timeSource.now >= deadline {
                return false
            }
            try? await timeSource.sleep(for: .milliseconds(50))
        }
    }

    private func tail(of process: any ManagedProcess) -> String {
        process.outputTail.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
