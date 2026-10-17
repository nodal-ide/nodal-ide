//
//  XdebugDetector.swift
//  CodeEdit
//
//  Detects Xdebug for the project's PHP runtime and reports its version/mode.
//

import Foundation
import SwiftUI

/// Inspects the resolved PHP interpreter for Xdebug (version + `xdebug.mode`) so PHP debugging can be
/// validated and guided. Never edits the user's `php.ini` — debugging is enabled per session via env.
@MainActor
final class XdebugDetector: ObservableObject {
    static let shared = XdebugDetector()

    enum Status: Equatable {
        case unknown
        case checking
        case noPHP
        case notInstalled(php: String)
        case loaded(php: String, version: String, mode: String)
    }

    @Published private(set) var status: Status = .unknown

    private init() {}

    /// Re-detects Xdebug for the given workspace (or the global default PHP when `workspace` is `nil`).
    func refresh(workspace: WorkspaceDocument? = nil) async {
        status = .checking
        guard let php = await Self.phpExecutable(workspace: workspace) else {
            status = .noPHP
            return
        }
        let version = await Self.run(
            "'\(php)' -r 'echo extension_loaded(\"xdebug\") ? phpversion(\"xdebug\") : \"\";' 2>/dev/null"
        )
        guard !version.isEmpty else {
            status = .notInstalled(php: php)
            return
        }
        let info = await Self.run("'\(php)' -i 2>/dev/null")
        let mode = Self.value(of: "xdebug.mode", in: info) ?? "off"
        status = .loaded(php: php, version: version, mode: mode)
    }

    // MARK: - Helpers

    /// The PHP executable for a workspace (project pin → global → newest installed), else `PATH`/system.
    static func phpExecutable(workspace: WorkspaceDocument?) async -> String? {
        if let runtime = await RuntimeResolver.resolve(kind: .php, workspace: workspace) {
            return runtime.executableDirectory.appending(path: "php").path(percentEncoded: false)
        }
        return RuntimeShell.whichAll("php").first
    }

    /// Extracts a `key => value` setting from `php -i` output.
    static func value(of key: String, in phpInfo: String) -> String? {
        for line in phpInfo.split(separator: "\n") {
            let parts = line.split(separator: "=>", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2, parts[0].caseInsensitiveCompare(key) == .orderedSame {
                return parts[1]
            }
        }
        return nil
    }

    private static func run(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: RuntimeShell.run(command))
            }
        }
    }
}
