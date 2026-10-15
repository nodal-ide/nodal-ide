//
//  RuntimeDiskUsage.swift
//  CodeEdit
//
//  Computes on-disk size for installed runtimes.
//

import Foundation

enum RuntimeDiskUsage {
    /// The size (in bytes) of a runtime's directory, or `nil` if it can't be determined.
    static func size(of url: URL) async -> Int64? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let output = RuntimeShell.run("du -sk '\(path)' 2>/dev/null")
                let kilobytes = output
                    .split(whereSeparator: { $0 == "\t" || $0 == " " })
                    .first
                    .flatMap { Int64($0) }
                continuation.resume(returning: kilobytes.map { $0 * 1024 })
            }
        }
    }

    /// Formats a byte count for display (e.g. `412 MB`).
    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
