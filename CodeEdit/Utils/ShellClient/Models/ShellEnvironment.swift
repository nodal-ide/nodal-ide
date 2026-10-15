//
//  ShellEnvironment.swift
//  CodeEdit
//
//  Builds an augmented PATH that includes common developer tool locations.
//

import Foundation

/// Provides a `PATH` that includes common Node/Homebrew install locations, so tools like `npm` resolve even
/// when the app is launched from a GUI (which doesn't load the user's interactive shell rc files, e.g. `nvm`).
enum ShellEnvironment {
    /// A `PATH` combining the current process `PATH` with discovered tool directories (deduped).
    static func augmentedPath() -> String {
        var parts = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in toolDirectories() where !parts.contains(dir) {
            parts.append(dir)
        }
        return parts.joined(separator: ":")
    }

    /// Homebrew/system directories plus discovered Node version managers (nvm, fnm, volta).
    static func toolDirectories() -> [String] {
        var dirs: [String] = []

        let home = FileManager.default.homeDirectoryForCurrentUser

        // nvm: ~/.nvm/versions/node/<version>/bin (newest first).
        let nvmRoot = home.appending(path: ".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot.path(percentEncoded: false)) {
            for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                dirs.append(nvmRoot.appending(path: version).appending(path: "bin").path(percentEncoded: false))
            }
        }

        // fnm
        dirs.append(home.appending(path: ".fnm/aliases/default/bin").path(percentEncoded: false))
        dirs.append(
            home.appending(path: "Library/Application Support/fnm/aliases/default/bin").path(percentEncoded: false)
        )

        // volta
        dirs.append(home.appending(path: ".volta/bin").path(percentEncoded: false))

        // Other language tool installs (cargo, go, pyenv, pip user scripts).
        dirs.append(home.appending(path: ".cargo/bin").path(percentEncoded: false))
        dirs.append(home.appending(path: "go/bin").path(percentEncoded: false))
        dirs.append(home.appending(path: ".pyenv/shims").path(percentEncoded: false))
        dirs.append(home.appending(path: ".local/bin").path(percentEncoded: false))
        dirs.append("/usr/local/go/bin")

        // Homebrew / system
        dirs += [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]

        return dirs.filter { FileManager.default.fileExists(atPath: $0) }
    }
}
