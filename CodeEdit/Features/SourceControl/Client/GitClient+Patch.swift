//
//  GitClient+Patch.swift
//  CodeEdit
//

import Foundation

extension GitClient {
    /// Applies a unified-diff patch to the index (staging) or its reverse (unstaging).
    ///
    /// - Parameters:
    ///   - patch: The unified diff text.
    ///   - cached: When `true`, applies to the index (`--cached`).
    ///   - reverse: When `true`, reverses the patch.
    func applyPatch(_ patch: String, cached: Bool = true, reverse: Bool = false) async throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeedit-\(UUID().uuidString).patch")
        try patch.write(to: temporaryURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        var command = "apply --recount"
        if cached {
            command += " --cached"
        }
        if reverse {
            command += " --reverse"
        }
        command += " " + temporaryURL.path.escapedDirectory()
        _ = try await run(command)
    }
}
