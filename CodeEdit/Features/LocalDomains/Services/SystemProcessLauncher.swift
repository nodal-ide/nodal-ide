import Darwin
import Foundation

/// Launches real child processes and supervises them as ``ManagedProcess`` instances.
@MainActor
final class SystemProcessLauncher: ProcessLaunching {
    private let timeSource: TimeSource

    init(timeSource: TimeSource = SystemTimeSource()) {
        self.timeSource = timeSource
    }

    func launch(
        _ request: ProcessLaunchRequest,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) throws -> any ManagedProcess {
        try SystemManagedProcess(request: request, timeSource: timeSource, onOutput: onOutput)
    }
}

/// A supervised child process: streams bounded stdout/stderr, tracks its PID, and stops gracefully
/// with a timeout before escalating to `SIGKILL`.
@MainActor
final class SystemManagedProcess: ManagedProcess {
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let outputBuffer: ProcessOutputBuffer
    private let timeSource: TimeSource
    private let onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    private var exitContinuations: [CheckedContinuation<ProcessExit, Never>] = []

    private(set) var pid: Int32 = 0
    private(set) var isRunning = false
    private(set) var exit: ProcessExit?

    /// A consistent, bounded copy of everything the process has written so far.
    var outputTail: [ProcessOutputLine] {
        outputBuffer.snapshot()
    }

    init(
        request: ProcessLaunchRequest,
        timeSource: TimeSource,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) throws {
        self.outputBuffer = ProcessOutputBuffer(limit: request.outputLimit)
        self.timeSource = timeSource
        self.onOutput = onOutput

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        if let environment = request.environment {
            process.environment = environment
        }
        if let workingDirectory = request.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        configureHandlers()
        try process.run()

        self.pid = process.processIdentifier
        self.isRunning = true
    }

    func waitForExit() async -> ProcessExit {
        if let exit {
            return exit
        }
        return await withCheckedContinuation { continuation in
            exitContinuations.append(continuation)
        }
    }

    func signal(_ signal: Int32) {
        send(signal)
    }

    func stop(signal: Int32, timeout: Duration) async {
        guard isRunning else {
            return
        }

        send(signal)
        if await waitUntilExited(within: timeout) {
            return
        }

        send(ProcessSignal.kill)
        _ = await waitForExit()
    }

    // MARK: - Handlers

    private func configureHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = makeReadHandler(stream: .stdout)
        stderrPipe.fileHandleForReading.readabilityHandler = makeReadHandler(stream: .stderr)

        process.terminationHandler = { [weak self] process in
            let reason: ProcessExit.Reason = process.terminationReason == .exit ? .exited : .signaled
            let exit = ProcessExit(status: process.terminationStatus, reason: reason)
            Task { @MainActor [weak self] in
                self?.finish(exit)
            }
        }
    }

    private func makeReadHandler(stream: ProcessOutputLine.Stream) -> @Sendable (FileHandle) -> Void {
        let buffer = outputBuffer
        let onOutput = onOutput
        return { handle in
            buffer.consume(handle.availableData, stream: stream, onOutput: onOutput)
        }
    }

    private func finish(_ exit: ProcessExit) {
        guard self.exit == nil else {
            return
        }

        process.terminationHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain anything the readability handlers had not picked up yet, then emit partial lines, so
        // `outputTail` is complete by the time `waitForExit()` resumes.
        outputBuffer.drain(handle: stdoutPipe.fileHandleForReading, stream: .stdout, onOutput: onOutput)
        outputBuffer.drain(handle: stderrPipe.fileHandleForReading, stream: .stderr, onOutput: onOutput)
        outputBuffer.flush(stream: .stdout, onOutput: onOutput)
        outputBuffer.flush(stream: .stderr, onOutput: onOutput)

        self.exit = exit
        isRunning = false

        let continuations = exitContinuations
        exitContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: exit)
        }
    }

    // MARK: - Signals

    private func send(_ signal: Int32) {
        let livePID = process.processIdentifier
        guard isRunning, livePID > 0, livePID == pid else {
            return
        }
        kill(livePID, signal)
    }

    private func waitUntilExited(within timeout: Duration) async -> Bool {
        guard exit == nil else {
            return true
        }

        let deadline = timeSource.now.addingTimeInterval(timeout.timeInterval)
        while exit == nil {
            if Task.isCancelled || timeSource.now >= deadline {
                return false
            }
            try? await timeSource.sleep(for: .milliseconds(20))
        }
        return true
    }
}

/// Thread-safe sink for a process's stdout/stderr: splits lines, keeps a bounded tail, and forwards
/// completed lines. Shared by the readability handlers and the final drain, so their reads never race.
private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var stdout = LineAccumulator()
    private var stderr = LineAccumulator()
    private var lines: [ProcessOutputLine] = []

    init(limit: Int) {
        self.limit = limit
    }

    func consume(
        _ data: Data,
        stream: ProcessOutputLine.Stream,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        append(accumulator(for: stream).append(data), stream: stream, onOutput: onOutput)
    }

    /// Reads whatever is immediately available without blocking (the pipe is switched to non-blocking
    /// mode so a stranded writer cannot wedge the caller).
    func drain(
        handle: FileHandle,
        stream: ProcessOutputLine.Stream,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }

        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }

        var bytes = [UInt8](repeating: 0, count: 65_536)
        let accumulator = accumulator(for: stream)
        while true {
            let bytesRead = read(descriptor, &bytes, bytes.count)
            guard bytesRead > 0 else {
                break
            }
            append(accumulator.append(Data(bytes[0..<bytesRead])), stream: stream, onOutput: onOutput)
        }
    }

    func flush(stream: ProcessOutputLine.Stream, onOutput: (@Sendable (ProcessOutputLine) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        append(accumulator(for: stream).flush(), stream: stream, onOutput: onOutput)
    }

    func snapshot() -> [ProcessOutputLine] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    private func accumulator(for stream: ProcessOutputLine.Stream) -> LineAccumulator {
        stream == .stdout ? stdout : stderr
    }

    private func append(
        _ newLines: [String],
        stream: ProcessOutputLine.Stream,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) {
        guard !newLines.isEmpty else {
            return
        }
        for line in newLines {
            let output = ProcessOutputLine(stream: stream, text: line)
            lines.append(output)
            onOutput?(output)
        }
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }
}

/// Thread-safe, newline-splitting buffer used by ``ProcessOutputBuffer``.
private final class LineAccumulator {
    private var buffer = ""

    func append(_ data: Data) -> [String] {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return []
        }

        buffer += text
        var lines: [String] = []
        while let index = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[buffer.startIndex..<index]))
            buffer = String(buffer[buffer.index(after: index)...])
        }
        return lines
    }

    func flush() -> [String] {
        guard !buffer.isEmpty else {
            return []
        }
        let remainder = buffer
        buffer = ""
        return [remainder]
    }
}
