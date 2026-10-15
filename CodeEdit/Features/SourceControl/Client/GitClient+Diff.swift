//
//  GitClient+Diff.swift
//  CodeEdit
//

import Foundation

extension GitClient {
    /// Returns the unified diff for a single path.
    ///
    /// - Parameters:
    ///   - path: The path (relative to the repository) to diff.
    ///   - staged: When `true`, diffs the index against `HEAD` (`--cached`); otherwise the working tree.
    /// - Returns: The raw unified diff text (may be empty).
    func diff(for path: String, staged: Bool = false) async throws -> String {
        var command = "diff --no-color"
        if staged {
            command += " --cached"
        }
        command += " -- \(path.escapedDirectory())"
        return try await run(command)
    }

    /// Returns the unified diff for the whole working tree (or index when `staged`).
    func diffAll(staged: Bool = false) async throws -> String {
        var command = "diff --no-color"
        if staged {
            command += " --cached"
        }
        return try await run(command)
    }
}
