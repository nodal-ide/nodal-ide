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

    /// Returns a context-free unified diff of a single path against `HEAD`.
    ///
    /// Used by the gutter change ribbon: `-U0` drops context lines, which are pure parse overhead when only the
    /// changed line numbers matter.
    func diffAgainstHEAD(for path: String) async throws -> String {
        try await run("diff --no-color --no-ext-diff -U0 HEAD -- \(path.escapedDirectory())")
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
