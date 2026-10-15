//
//  GitClient+Blame.swift
//  CodeEdit
//

import Foundation

extension GitClient {
    /// Returns `git blame --line-porcelain` output for a path.
    /// - Parameter path: The path (relative to the repository) to blame.
    func blame(for path: String) async throws -> String {
        try await run("blame --line-porcelain -- \(path.escapedDirectory())")
    }
}
