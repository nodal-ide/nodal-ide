import Darwin
import Foundation
@testable import CodeEdit

final class FakeTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date
    private var sleeps: [Duration] = []

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.currentDate = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return currentDate
    }

    var recordedSleeps: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return sleeps
    }

    func sleep(for duration: Duration) async throws {
        recordSleep(duration)
    }

    private func recordSleep(_ duration: Duration) {
        lock.lock()
        sleeps.append(duration)
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
        lock.unlock()
    }

    func advance(by duration: Duration) {
        lock.lock()
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
        lock.unlock()
    }
}

final class FakePortProber: PortProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool]
    private var probedPorts: [Int] = []

    /// Called after each probe with the zero-based probe index.
    var onProbe: (@MainActor @Sendable (Int) -> Void)?

    /// Results are consumed once per probe while more than one remains; the final element is sticky.
    init(results: [Bool] = [false]) {
        self.results = results
    }

    var probedPortNumbers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return probedPorts
    }

    func isReachable(host: String, port: Int, timeout: Duration) async -> Bool {
        let (index, result) = recordProbe(port: port)

        if let onProbe {
            await MainActor.run {
                onProbe(index)
            }
        }
        return result
    }

    private func recordProbe(port: Int) -> (Int, Bool) {
        lock.lock()
        defer { lock.unlock() }
        let index = probedPorts.count
        probedPorts.append(port)
        let result: Bool
        if results.count > 1 {
            result = results.removeFirst()
        } else {
            result = results.first ?? false
        }
        return (index, result)
    }
}

final class FakeUnixSocketProber: UnixSocketProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool]
    private var probedPaths: [String] = []

    /// Called after each probe with the zero-based probe index.
    var onProbe: (@MainActor @Sendable (Int) -> Void)?

    /// Results are consumed once per probe while more than one remains; the final element is sticky.
    init(results: [Bool] = [false]) {
        self.results = results
    }

    var probedSocketPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return probedPaths
    }

    func isConnectable(path: String, timeout: Duration) async -> Bool {
        let (index, result) = recordProbe(path: path)
        if let onProbe {
            await MainActor.run {
                onProbe(index)
            }
        }
        return result
    }

    private func recordProbe(path: String) -> (Int, Bool) {
        lock.lock()
        defer { lock.unlock() }
        let index = probedPaths.count
        probedPaths.append(path)
        let result: Bool
        if results.count > 1 {
            result = results.removeFirst()
        } else {
            result = results.first ?? false
        }
        return (index, result)
    }
}

@MainActor
final class FakeManagedProcess: ManagedProcess {
    struct StopRequest: Equatable {
        let signal: Int32
        let timeout: Duration
    }

    var pid: Int32
    var isRunning: Bool
    var exit: ProcessExit?
    var outputTail: [ProcessOutputLine] = []
    private(set) var receivedStops: [StopRequest] = []
    private(set) var receivedSignals: [Int32] = []
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []

    init(pid: Int32 = 1) {
        self.pid = pid
        self.isRunning = true
    }

    func waitForExit() async -> ProcessExit {
        if let exit {
            return exit
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func stop(signal: Int32, timeout: Duration) async {
        receivedStops.append(StopRequest(signal: signal, timeout: timeout))
        finish(ProcessExit(status: 0, reason: .exited))
    }

    func signal(_ signal: Int32) {
        receivedSignals.append(signal)
    }

    func finish(_ exit: ProcessExit) {
        guard self.exit == nil else { return }
        self.exit = exit
        isRunning = false
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: exit)
        }
    }

    func append(_ line: ProcessOutputLine) {
        outputTail.append(line)
    }
}

@MainActor
final class FakeProcessLauncher: ProcessLaunching {
    struct Launch {
        let request: ProcessLaunchRequest
        let process: FakeManagedProcess
    }

    private(set) var launches: [Launch] = []
    private(set) var outputHandler: (@Sendable (ProcessOutputLine) -> Void)?
    var launchError: Error?

    func launch(
        _ request: ProcessLaunchRequest,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) throws -> any ManagedProcess {
        if let launchError {
            throw launchError
        }

        let process = FakeManagedProcess(pid: Int32(launches.count + 1))
        launches.append(Launch(request: request, process: process))
        outputHandler = onOutput
        return process
    }
}

final class FakePHPFPMProcessInspector: PHPFPMProcessInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var runningPIDs: Set<Int32> = []
    private var executablePaths: [Int32: String] = [:]
    private var argumentsByPID: [Int32: [String]] = [:]
    private var loggedSignals: [Int32] = []

    var ignoresQuit = false

    func setRunning(_ pid: Int32, executable: String, arguments: [String]) {
        lock.lock()
        runningPIDs.insert(pid)
        executablePaths[pid] = executable
        argumentsByPID[pid] = arguments
        lock.unlock()
    }

    func setAlive(_ pid: Int32) {
        lock.lock()
        runningPIDs.insert(pid)
        lock.unlock()
    }

    var signals: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return loggedSignals
    }

    func isRunning(pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningPIDs.contains(pid)
    }

    func executablePath(pid: Int32) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return executablePaths[pid]
    }

    func arguments(pid: Int32) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        return argumentsByPID[pid]
    }

    func signal(_ signal: Int32, to pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loggedSignals.append(signal)
        if signal == SIGKILL || (signal == SIGQUIT && !ignoresQuit) {
            runningPIDs.remove(pid)
        }
        return true
    }
}
