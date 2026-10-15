//
//  RuntimeShell.swift
//  CodeEdit
//
//  Small helper for running shell commands during runtime discovery/installation.
//

import Foundation

enum RuntimeShell {
    /// Runs a command in a non-interactive login shell and returns its trimmed stdout.
    @discardableResult
    static func run(_ command: String) -> String {
        runResult(command).output
    }

    /// Runs a command and returns its trimmed combined output and exit status.
    static func runResult(_ command: String) -> (output: String, status: Int32) {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/zsh")
        task.arguments = ["-lc", command]
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
