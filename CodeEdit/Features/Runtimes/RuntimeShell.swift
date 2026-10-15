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
        let task = Process()
        task.executableURL = URL(filePath: "/bin/zsh")
        task.arguments = ["-lc", command]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
