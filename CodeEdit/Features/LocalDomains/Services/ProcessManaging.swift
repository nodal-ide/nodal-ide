import Darwin
import Foundation

enum ProcessSignal {
    static let terminate: Int32 = SIGTERM
    static let quit: Int32 = SIGQUIT
    static let kill: Int32 = SIGKILL
    static let hangup: Int32 = SIGHUP
    static let reopen: Int32 = SIGUSR1
}

struct ProcessOutputLine: Equatable, Sendable {
    enum Stream: String, Sendable {
        case stdout
        case stderr
    }

    let stream: Stream
    let text: String
}

struct ProcessLaunchRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let workingDirectory: URL?
    let outputLimit: Int

    init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        outputLimit: Int = 500
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.outputLimit = max(1, outputLimit)
    }
}

struct ProcessExit: Equatable, Sendable {
    enum Reason: String, Sendable {
        case exited
        case signaled
    }

    let status: Int32
    let reason: Reason

    var isSuccess: Bool {
        reason == .exited && status == 0
    }
}

@MainActor
protocol ManagedProcess: AnyObject {
    var pid: Int32 { get }
    var isRunning: Bool { get }
    var exit: ProcessExit? { get }
    var outputTail: [ProcessOutputLine] { get }

    func waitForExit() async -> ProcessExit
    func signal(_ signal: Int32)
    func stop(signal: Int32, timeout: Duration) async
}

extension ManagedProcess {
    func stop(timeout: Duration = .seconds(5)) async {
        await stop(signal: ProcessSignal.terminate, timeout: timeout)
    }
}

@MainActor
protocol ProcessLaunching: AnyObject {
    func launch(
        _ request: ProcessLaunchRequest,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?
    ) throws -> any ManagedProcess
}

extension ProcessLaunching {
    func launch(_ request: ProcessLaunchRequest) throws -> any ManagedProcess {
        try launch(request, onOutput: nil)
    }
}
