//
//  DebugAdapterClient.swift
//  CodeEdit
//
//  Speaks the Debug Adapter Protocol over a spawned adapter process' stdio.
//

import Foundation

/// A minimal DAP client: spawns an adapter process and sends/receives `Content-Length`-framed JSON messages.
///
/// Requests are sent with ``send(command:arguments:)`` which awaits the matching response. Adapter events are
/// delivered through ``onEvent``. All callbacks are invoked on the main actor.
@MainActor
final class DebugAdapterClient {
    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let workingDirectory: URL?

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private var buffer = Data()
    private var sequence = 0
    private var pending: [Int: CheckedContinuation<DAPResponse, Error>] = [:]

    /// Called for each event received from the adapter.
    var onEvent: ((DAPEvent) -> Void)?
    /// Called when the adapter process terminates (with its status).
    var onTerminated: ((Int32) -> Void)?
    /// Called with the adapter's stderr output (and lifecycle logs).
    var onLog: ((String) -> Void)?

    var isRunning: Bool { process.isRunning }

    init(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    // MARK: - Lifecycle

    func start() throws {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.ingest(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            DispatchQueue.main.async { self?.onLog?(text) }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.handleTermination(proc.terminationStatus) }
        }

        try process.run()
    }

    func stop() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        failPending(with: DAPError.terminated)
    }

    // MARK: - Sending

    func send(command: String, arguments: JSONValue? = nil) async throws -> DAPResponse {
        guard process.isRunning else { throw DAPError.notRunning }

        sequence += 1
        let requestSeq = sequence
        let request = DAPRequest(seq: requestSeq, command: command, arguments: arguments)
        let json = try JSONEncoder().encode(request)
        var frame = Data("Content-Length: \(json.count)\r\n\r\n".utf8)
        frame.append(json)

        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: frame)
        } catch {
            throw DAPError.writeFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[requestSeq] = continuation
        }
    }

    // MARK: - Receiving

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let frame = extractFrame() {
            handle(frame)
        }
    }

    /// Pulls a single `Content-Length`-framed message off the buffer, if a complete one is available.
    private func extractFrame() -> Data? {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let separatorRange = buffer.range(of: separator) else { return nil }

        let headerData = buffer[buffer.startIndex..<separatorRange.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8),
              let length = Self.contentLength(from: header) else {
            // Malformed header — drop it and resync.
            buffer = Data(buffer[separatorRange.upperBound...])
            return nil
        }

        let bodyStart = separatorRange.upperBound
        let available = buffer.count - (bodyStart - buffer.startIndex)
        guard available >= length else { return nil }

        let bodyEnd = bodyStart + length
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer = Data(buffer[bodyEnd...])
        return body
    }

    private static func contentLength(from header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private func handle(_ data: Data) {
        guard let peek = try? JSONDecoder().decode(DAPTypePeek.self, from: data) else { return }
        switch peek.type {
        case "response":
            guard let response = try? JSONDecoder().decode(DAPResponse.self, from: data) else { return }
            pending.removeValue(forKey: response.requestSeq)?.resume(returning: response)
        case "event":
            guard let event = try? JSONDecoder().decode(DAPEvent.self, from: data) else { return }
            onEvent?(event)
        default:
            break
        }
    }

    private func handleTermination(_ status: Int32) {
        failPending(with: DAPError.terminated)
        onTerminated?(status)
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
