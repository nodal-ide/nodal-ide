//
//  PHPAdapterInstaller.swift
//  CodeEdit
//
//  Detects and installs a PHP Debug Adapter (vscode-php-debug) for Xdebug debugging.
//

import Foundation
import SwiftUI

/// Detects and installs a PHP DAP adapter, and registers it in the Developer settings
/// (`debugAdapters["php"]`) so ``DebuggerAutoWiring`` picks it up.
@MainActor
final class PHPAdapterInstaller: ObservableObject {
    static let shared = PHPAdapterInstaller()

    enum Status: Equatable {
        case unknown
        case notInstalled
        case installing
        case installed(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .unknown

    static let adapterID = "php"

    /// Where we install the adapter: `~/Library/Application Support/CodeEdit/Debug Adapters/php`.
    static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CodeEdit/Debug Adapters/php")
    }

    /// A small launcher script that runs the adapter under `node`.
    static var wrapperURL: URL {
        installDirectory.appending(path: "php-debug-adapter")
    }

    private init() {}

    // MARK: - Detection

    /// The adapter to use: the configured one, the app-installed wrapper, or one on `PATH`.
    static func detectedAdapterPath() -> String? {
        let configured = Settings.shared.preferences.developerSettings.debugAdapters[adapterID]
        if let configured, !configured.isEmpty,
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        let wrapper = wrapperURL.path(percentEncoded: false)
        if FileManager.default.isExecutableFile(atPath: wrapper) {
            return wrapper
        }
        for candidate in ["php-debug-adapter", "php-debug"] where RuntimeShell.whichAll(candidate).first != nil {
            return RuntimeShell.whichAll(candidate).first
        }
        return nil
    }

    static func isInstalled() -> Bool { detectedAdapterPath() != nil }

    /// Recomputes ``status`` from the current system state.
    func refresh() {
        if let path = Self.detectedAdapterPath() {
            status = .installed(path)
        } else {
            status = .notInstalled
        }
    }

    // MARK: - Install

    /// Installs `vscode-php-debug` via npm, writes a launcher wrapper, and registers it.
    func install() async {
        status = .installing
        let directory = Self.installDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.path(percentEncoded: false)

        // Use the resolved Node runtime (global default -> newest installed), like the terminal, and
        // fall back to discovered nvm/fnm/Homebrew so `npm` resolves.
        var searchPath = ShellEnvironment.augmentedPath()
        if let node = await RuntimeResolver.resolve(kind: .node, workspace: nil) {
            searchPath = node.executableDirectory.path(percentEncoded: false) + ":" + searchPath
        }
        let result = await Self.run(
            "export PATH=\"\(searchPath)\"; cd '\(path)' && npm install vscode-php-debug --no-fund --no-audit 2>&1"
        )
        guard result.status == 0 else {
            let message = result.output.isEmpty ? "npm install failed." : result.output
            status = .failed(message)
            Self.report(
                success: false,
                message: "Couldn't install the PHP debug adapter. Is Node.js/npm installed?"
            )
            return
        }

        guard let entry = Self.findEntry(in: directory) else {
            status = .failed("Installed, but couldn't locate the adapter entry point.")
            return
        }
        let wrapperPath = Self.wrapperURL.path(percentEncoded: false)
        let runLine = entry.hasSuffix(".js")
            ? "exec node \"\(entry)\" \"$@\""
            : "exec \"\(entry)\" \"$@\""
        do {
            try "#!/bin/sh\n\(runLine)\n".write(to: Self.wrapperURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        Settings.shared.preferences.developerSettings.debugAdapters[Self.adapterID] = wrapperPath
        status = .installed(wrapperPath)
        Self.report(success: true, message: "PHP debug adapter installed.")
    }

    // MARK: - Helpers

    /// Finds the adapter's entry point within an install directory (npm bin, else the JS entry).
    static func findEntry(in directory: URL) -> String? {
        let candidates = [
            directory.appending(path: "node_modules/.bin/php-debug-adapter"),
            directory.appending(path: "node_modules/.bin/phpDebug"),
            directory.appending(path: "node_modules/vscode-php-debug/out/phpDebug.js"),
            directory.appending(path: "node_modules/vscode-php-debug/phpDebug.js")
        ]
        return candidates
            .map { $0.path(percentEncoded: false) }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func run(_ command: String) async -> (output: String, status: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: RuntimeShell.runResult(command))
            }
        }
    }

    private static func report(success: Bool, message: String) {
        _ = NotificationManager.shared.post(
            iconSymbol: success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
            iconColor: success ? .green : .orange,
            title: success ? "PHP Debug Adapter" : "PHP Debug Adapter",
            description: message,
            actionButtonTitle: "Dismiss",
            action: {},
            isSticky: !success
        )
    }
}
