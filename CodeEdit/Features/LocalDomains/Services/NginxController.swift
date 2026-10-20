import Foundation

enum NginxControllerError: Error, Equatable, LocalizedError {
    case portInUse(Int)
    case alreadyRunning
    case notRunning
    case launchFailed(message: String)
    case exitedDuringStartup(status: Int32, message: String)
    case readinessTimedOut(port: Int)
    case validationFailed(message: String)
    case reloadFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .portInUse(let port):
            return "Port \(port) is already in use. Stop the process using it and try again."
        case .alreadyRunning:
            return "nginx is already running."
        case .notRunning:
            return "nginx is not running."
        case .launchFailed(let message):
            return "Could not start nginx: \(message)"
        case let .exitedDuringStartup(status, message):
            let detail = message.isEmpty ? "" : " \(message)"
            return "nginx exited during startup with status \(status).\(detail)"
        case .readinessTimedOut(let port):
            return "nginx did not start listening on port \(port) in time."
        case .validationFailed(let message):
            return "The nginx configuration was rejected: \(message)"
        case .reloadFailed(let message):
            let detail = message.isEmpty ? "" : " \(message)"
            return "nginx could not load the new configuration.\(detail)"
        }
    }
}

enum NginxControllerState: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case stopping
    case failed(NginxControllerError)
}

/// Owns the single app-managed nginx master: busy-port detection, launch, readiness, generation swaps,
/// `SIGHUP` reloads, rollback, and clean stop. It never kills a foreign process; a busy port is reported
/// as an actionable error.
@MainActor
final class NginxController {
    let prefix: NginxPrefix

    private let launcher: any ProcessLaunching
    private let prober: any PortProbing
    private let validator: any NginxConfigValidating
    private let timeSource: TimeSource
    private let store: NginxGenerationStore
    private let readinessTimeout: Duration
    private let stopTimeout: Duration
    private let probeTimeout = Duration.milliseconds(250)

    private var process: (any ManagedProcess)?
    private(set) var executableURL: URL?

    private(set) var state: NginxControllerState = .stopped

    init(
        launcher: (any ProcessLaunching)? = nil,
        prober: any PortProbing = SocketPortProbe(),
        validator: (any NginxConfigValidating)? = nil,
        timeSource: TimeSource = SystemTimeSource(),
        prefix: NginxPrefix = .default,
        readinessTimeout: Duration = .seconds(10),
        stopTimeout: Duration = .seconds(5)
    ) {
        self.launcher = launcher ?? SystemProcessLauncher()
        self.prober = prober
        self.validator = validator ?? NginxConfigValidator()
        self.timeSource = timeSource
        self.prefix = prefix
        self.store = NginxGenerationStore(prefix: prefix)
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

    var currentGenerationName: String? {
        store.currentName()
    }

    var outputTail: [ProcessOutputLine] {
        process?.outputTail ?? []
    }

    /// Writes, validates, and publishes a config generation. Starts the master if needed, otherwise
    /// reloads it with `SIGHUP`. A rejected generation is never published.
    func apply(
        executableURL: URL,
        sites: [NginxSiteConfiguration],
        listenPorts: Set<Int>
    ) async throws {
        self.executableURL = executableURL

        let previous = store.currentName()
        let name = try store.nextName()
        let configURL = try store.write(sites: sites, listenPorts: listenPorts, name: name)

        let validation = await validator.validate(
            configURL: configURL,
            prefix: prefix,
            executableURL: executableURL
        )
        if case .invalid(let message) = validation {
            try? store.remove(name: name)
            throw NginxControllerError.validationFailed(message: message)
        }

        try store.swapCurrent(to: name)

        guard isRunning else {
            do {
                try await start(
                    executableURL: executableURL,
                    configURL: prefix.currentSymlink.appending(path: "nginx.conf"),
                    listenPorts: listenPorts
                )
                try? store.prune(keeping: keepSet(name: name, previous: previous))
            } catch {
                try? store.remove(name: name)
                restoreCurrent(to: previous)
                throw error
            }
            return
        }

        guard let process else {
            throw NginxControllerError.notRunning
        }

        process.signal(ProcessSignal.hangup)
        if await waitForReloadHealth(process: process) {
            try? store.prune(keeping: keepSet(name: name, previous: previous))
            return
        }

        if let previous, process.exit == nil {
            try? store.swapCurrent(to: previous)
            process.signal(ProcessSignal.hangup)
            _ = await waitForReloadHealth(process: process)
            try? store.remove(name: name)
        }

        let failure = NginxControllerError.reloadFailed(message: tail(of: process))
        if process.exit != nil {
            state = .failed(failure)
        }
        throw failure
    }

    func start(executableURL: URL, configURL: URL, listenPorts: Set<Int>) async throws {
        if let process, process.isRunning, process.exit == nil {
            throw NginxControllerError.alreadyRunning
        }
        self.process = nil
        self.executableURL = executableURL
        state = .starting

        for port in listenPorts.sorted() where await prober.isReachable(
            host: "127.0.0.1",
            port: port,
            timeout: probeTimeout
        ) {
            state = .stopped
            throw NginxControllerError.portInUse(port)
        }

        let request = ProcessLaunchRequest(
            executableURL: executableURL,
            arguments: [
                "-p", prefix.root.path(percentEncoded: false),
                "-c", configURL.path(percentEncoded: false)
            ],
            outputLimit: 200
        )

        let process: any ManagedProcess
        do {
            process = try launcher.launch(request)
        } catch {
            let failure = NginxControllerError.launchFailed(message: error.localizedDescription)
            state = .failed(failure)
            throw failure
        }
        self.process = process

        guard let port = listenPorts.sorted().first else {
            state = .running(pid: process.pid)
            return
        }

        if await waitUntilReady(process: process, port: port) {
            state = .running(pid: process.pid)
            return
        }

        await process.stop(signal: ProcessSignal.quit, timeout: stopTimeout)
        self.process = nil

        if let exit = process.exit, !exit.isSuccess {
            let failure = NginxControllerError.exitedDuringStartup(status: exit.status, message: tail(of: process))
            state = .failed(failure)
            throw failure
        }

        let failure = NginxControllerError.readinessTimedOut(port: port)
        state = .failed(failure)
        throw failure
    }

    func stop() async {
        guard let process else {
            state = .stopped
            return
        }
        state = .stopping
        await process.stop(signal: ProcessSignal.quit, timeout: stopTimeout)
        self.process = nil
        state = .stopped
    }

    /// Tells the master to reopen its log files (`SIGUSR1`), e.g. after rotation renamed them aside.
    func reopenLogs() {
        process?.signal(ProcessSignal.reopen)
    }

    /// Rotates any log that exceeds `maxBytes` and asks the master to reopen the files it just released.
    /// Returns the URLs that were rotated.
    @discardableResult
    func rotateLogs(_ urls: [URL], maxBytes: Int, keep: Int = 2) throws -> [URL] {
        var rotated: [URL] = []
        for url in urls where try LogFileRotator.rotateIfNeeded(url, maxBytes: maxBytes, keep: keep) {
            rotated.append(url)
        }
        if !rotated.isEmpty {
            process?.signal(ProcessSignal.reopen)
        }
        return rotated
    }

    private func waitUntilReady(process: any ManagedProcess, port: Int) async -> Bool {
        let deadline = timeSource.now.addingTimeInterval(readinessTimeout.timeInterval)
        while true {
            if await prober.isReachable(host: "127.0.0.1", port: port, timeout: probeTimeout) {
                return true
            }
            if process.exit != nil || Task.isCancelled || timeSource.now >= deadline {
                return false
            }
            try? await timeSource.sleep(for: .milliseconds(50))
        }
    }

    /// Reloads are asynchronous in the master; give it a moment and verify it survived before pruning.
    private func waitForReloadHealth(process: any ManagedProcess) async -> Bool {
        try? await timeSource.sleep(for: .milliseconds(100))
        return process.exit == nil
    }

    private func keepSet(name: String, previous: String?) -> Set<String> {
        var keep: Set<String> = [name]
        if let previous {
            keep.insert(previous)
        }
        return keep
    }

    private func restoreCurrent(to previous: String?) {
        if let previous {
            try? store.swapCurrent(to: previous)
        } else {
            try? FileManager.default.removeItem(at: prefix.currentSymlink)
        }
    }

    private func tail(of process: any ManagedProcess) -> String {
        process.outputTail.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
