//
//  CommandRunner.swift
//  CodeEdit
//
//  Runs short-lived command-line tools for extension authoring without a shell.
//

import Foundation

struct CommandOutput: Sendable, Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum CommandRunnerError: LocalizedError {
    case launchFailed(String)
    case outputTooLarge
    case failed(command: String, status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Couldn’t start the command: \(message)"
        case .outputTooLarge:
            return "The command produced too much output."
        case let .failed(command, status, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) failed with status \(status)\(detail.isEmpty ? "." : ": \(detail)")"
        }
    }
}

/// Executes a tool with argument-safe process APIs and bounded output.
///
/// Output is spooled to temporary files rather than pipes so a command can never deadlock by filling
/// a pipe buffer before it exits.
struct CommandRunner: Sendable {
    private static let maximumOutputBytes = 8 * 1_024 * 1_024

    func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        acceptedStatuses: Set<Int32> = [0]
    ) async throws -> CommandOutput {
        let prepared = try prepare(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment
        )
        defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
        return try await wait(
            for: prepared.process,
            box: prepared.box,
            commandName: prepared.commandName,
            acceptedStatuses: acceptedStatuses
        )
    }

    private struct PreparedProcess {
        let process: Process
        let box: ProcessBox
        let temporaryRoot: URL
        let commandName: String
    }

    private func prepare(
        executable: URL,
        arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]
    ) throws -> PreparedProcess {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "NodalCommand-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let stdoutURL = temporaryRoot.appending(path: "stdout")
        let stderrURL = temporaryRoot.appending(path: "stderr")
        guard fileManager.createFile(atPath: stdoutURL.path(percentEncoded: false), contents: nil),
              fileManager.createFile(atPath: stderrURL.path(percentEncoded: false), contents: nil) else {
            throw CommandRunnerError.launchFailed("Could not create temporary output files.")
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.standardInput = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let box = ProcessBox(
            process: process,
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle,
            stdoutURL: stdoutURL,
            stderrURL: stderrURL
        )
        return PreparedProcess(
            process: process,
            box: box,
            temporaryRoot: temporaryRoot,
            commandName: executable.lastPathComponent
        )
    }

    private func wait(
        for process: Process,
        box: ProcessBox,
        commandName: String,
        acceptedStatuses: Set<Int32>
    ) async throws -> CommandOutput {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    let result = box.finish(status: finished.terminationStatus)
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    switch result {
                    case .success(let output):
                        guard acceptedStatuses.contains(output.status) else {
                            continuation.resume(throwing: CommandRunnerError.failed(
                                command: commandName,
                                status: output.status,
                                message: output.stderr.isEmpty ? output.stdout : output.stderr
                            ))
                            return
                        }
                        continuation.resume(returning: output)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                } catch {
                    box.closeHandles()
                    continuation.resume(throwing: CommandRunnerError.launchFailed(
                        error.localizedDescription
                    ))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let stdoutURL: URL
    private let stderrURL: URL
    private let lock = NSLock()
    private var didCloseHandles = false

    init(
        process: Process,
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        stdoutURL: URL,
        stderrURL: URL
    ) {
        self.process = process
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
        self.stdoutURL = stdoutURL
        self.stderrURL = stderrURL
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    func closeHandles() {
        lock.lock()
        defer { lock.unlock() }
        guard !didCloseHandles else { return }
        didCloseHandles = true
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    func finish(status: Int32) -> Result<CommandOutput, CommandRunnerError> {
        closeHandles()
        guard let stdout = read(stdoutURL), let stderr = read(stderrURL) else {
            return .failure(.outputTooLarge)
        }
        return .success(CommandOutput(
            status: status,
            stdout: String(bytes: stdout, encoding: .utf8) ?? "",
            stderr: String(bytes: stderr, encoding: .utf8) ?? ""
        ))
    }

    private func read(_ url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        ), let size = (attributes[.size] as? NSNumber)?.intValue,
           size <= 8 * 1_024 * 1_024 else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
