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
        let configured = AppServices.settings.preferences.developerSettings.debugAdapters[adapterID]
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

    /// Downloads the PHP Debug extension (VSIX) from Open VSX, extracts the compiled adapter, writes a
    /// launcher wrapper, and registers it.
    ///
    /// The extension isn't published to npm, so we fetch the built VSIX (which includes `out/` +
    /// `node_modules`) rather than building from source.
    func install() async {
        status = .installing

        guard let downloadURL = await Self.latestVSIXURL() else {
            status = .failed("Couldn't reach the Open VSX registry.")
            Self.report(success: false, message: "Couldn't reach Open VSX to download the PHP debug adapter.")
            return
        }

        let vsix = FileManager.default.temporaryDirectory.appending(path: "xdebug-php-debug.vsix")
        do {
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            try data.write(to: vsix)
        } catch {
            status = .failed(error.localizedDescription)
            Self.report(success: false, message: "Download failed: \(error.localizedDescription)")
            return
        }

        let directory = Self.installDirectory
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vsixPath = vsix.path(percentEncoded: false)
        let directoryPath = directory.path(percentEncoded: false)
        let result = await Self.run("unzip -o '\(vsixPath)' -d '\(directoryPath)' >/dev/null 2>&1")
        try? FileManager.default.removeItem(at: vsix)
        guard result.status == 0, let entry = Self.findEntry(in: directory) else {
            status = .failed("Couldn't extract the debug adapter from the package.")
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

        AppServices.settings.preferences.developerSettings.debugAdapters[Self.adapterID] = wrapperPath
        status = .installed(wrapperPath)
        Self.report(success: true, message: "PHP debug adapter installed.")
    }

    // MARK: - Helpers

    /// The latest PHP Debug `.vsix` download URL from Open VSX.
    static func latestVSIXURL() async -> URL? {
        guard let url = URL(string: "https://open-vsx.org/api/xdebug/php-debug") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let files = object["files"] as? [String: Any],
           let download = files["download"] as? String,
           let downloadURL = URL(string: download) {
            return downloadURL
        }
        if let version = object["version"] as? String {
            return URL(
                string: "https://open-vsx.org/api/xdebug/php-debug/\(version)/file/xdebug.php-debug-\(version).vsix"
            )
        }
        return nil
    }

    /// Finds the adapter's entry point within an install directory (VSIX layout or npm layout).
    static func findEntry(in directory: URL) -> String? {
        let candidates = [
            directory.appending(path: "extension/out/phpDebug.js"),
            directory.appending(path: "extension/phpDebug.js"),
            directory.appending(path: "out/phpDebug.js"),
            directory.appending(path: "node_modules/vscode-php-debug/out/phpDebug.js"),
            directory.appending(path: "node_modules/.bin/php-debug-adapter")
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
