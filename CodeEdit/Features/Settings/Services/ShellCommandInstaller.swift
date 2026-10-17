//
//  ShellCommandInstaller.swift
//  CodeEdit
//

import AppKit
import Foundation

/// Installs the bundled `codeedit` shim into `/usr/local/bin` as a symbolic link, falling back to an
/// elevated `osascript` install when the sandbox refuses to create the link directly.
///
/// Extracted from `GeneralSettingsView` so the settings UI stays declarative.
enum ShellCommandInstaller {
    static let destinationPath = "/usr/local/bin/codeedit"

    static func install() {
        guard let commandPath = Bundle.main
            .url(forResource: "codeedit", withExtension: nil, subdirectory: "Resources")?.path else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }
        } catch {
            return
        }

        NSWorkspace.shared.requestAuthorization(to: .createSymbolicLink) { auth, error in
            guard let auth, error == nil else {
                elevateAndLink(commandPath: commandPath, destinationPath: destinationPath)
                return
            }
            do {
                try FileManager(authorization: auth).createSymbolicLink(
                    atPath: destinationPath, withDestinationPath: commandPath
                )
            } catch {
                elevateAndLink(commandPath: commandPath, destinationPath: destinationPath)
            }
        }
    }

    private static func elevateAndLink(commandPath: String, destinationPath: String) {
        let script = [
            "osascript", "-e",
            "\"do shell script \\\"mkdir -p /usr/local/bin && ln -sf '\(commandPath)' '\(destinationPath)'\\\"\"",
            "with administrator privileges"
        ].joined(separator: " ")

        let task = Process()
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        task.arguments = ["-c", script]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.standardInput = nil
        try? task.run()
    }
}
