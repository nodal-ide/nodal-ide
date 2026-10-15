//
//  RuntimeShell.swift
//  CodeEdit
//
//  Small helper for running shell commands during runtime discovery/installation.
//

import Foundation

enum RuntimeShell {
    /// Common tool locations appended to `PATH` so Homebrew/system tools resolve even when a GUI app
    /// launches us without the user's shell `PATH` (login shells from Finder/Xcode don't source `.zshrc`).
    static let extraPathDirectories = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",
        "/usr/local/bin", "/usr/local/sbin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ]

    /// Runs a command in a non-interactive login shell and returns its trimmed stdout.
    @discardableResult
    static func run(_ command: String) -> String {
        runResult(command).output
    }

    /// Runs a command and returns its trimmed combined output and exit status.
    static func runResult(_ command: String) -> (output: String, status: Int32) {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/zsh")
        // `export PATH` runs after the login profiles, guaranteeing Homebrew/system tools are reachable.
        let extras = extraPathDirectories.joined(separator: ":")
        task.arguments = ["-lc", "export PATH=\"$PATH:\(extras)\"; \(command)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return ("", -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, task.terminationStatus)
    }

    /// Runs a command in a login shell, streaming output lines, and returns its exit status.
    ///
    /// Cancelling the calling task terminates the process (used to stop installs).
    static func runStreaming(
        _ command: String,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        let extras = extraPathDirectories.joined(separator: ":")
        process.arguments = ["-lc", "export PATH=\"$PATH:\(extras)\"; \(command)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let buffer = LineBuffer(onLine: onLine)
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    buffer.append(handle.availableData)
                }
                process.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    buffer.flush()
                    continuation.resume(returning: proc.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// Runs a command and returns its non-empty output lines.
    static func lines(_ command: String) -> [String] {
        run(command)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Resolves all executables named `name` on the PATH.
    static func whichAll(_ name: String) -> [String] {
        lines("which -a \(name) 2>/dev/null")
    }
}

/// Accumulates `readabilityHandler` chunks and splits them into lines (thread-safe).
private final class LineBuffer: @unchecked Sendable {
    private let onLine: @Sendable (String) -> Void
    private var buffer = ""
    private let lock = NSLock()

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer += text
        var lines: [String] = []
        while let index = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[buffer.startIndex..<index]))
            buffer = String(buffer[buffer.index(after: index)...])
        }
        lock.unlock()
        for line in lines {
            onLine(line)
        }
    }

    func flush() {
        lock.lock()
        let remainder = buffer
        buffer = ""
        lock.unlock()
        if !remainder.isEmpty {
            onLine(remainder)
        }
    }
}
