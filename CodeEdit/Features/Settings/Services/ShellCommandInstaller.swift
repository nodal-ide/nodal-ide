//
//  ShellCommandInstaller.swift
//  CodeEdit
//

import Foundation

enum ShellCommandInstallError: LocalizedError {
    case writeFailed(String)
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let message):
            "Could not install the shell command: \(message)"
        case .authorizationFailed(let message):
            "Could not install the shell command with administrator privileges: \(message)"
        }
    }
}

@MainActor
enum ShellCommandInstaller {
    static let commandName = "nodal"
    static let installationURL = URL(fileURLWithPath: "/usr/local/bin/nodal")

    static func isInstalled(
        appPath: String = Bundle.main.bundlePath,
        at destination: URL = installationURL
    ) -> Bool {
        guard let contents = try? String(contentsOf: destination, encoding: .utf8) else {
            return false
        }
        return contents == wrapperScript(appPath: appPath)
    }

    static func install(
        appPath: String = Bundle.main.bundlePath,
        at destination: URL = installationURL
    ) async -> Result<Void, Error> {
        let script = wrapperScript(appPath: appPath)

        do {
            try write(script, to: destination)
            guard isInstalled(appPath: appPath, at: destination) else {
                throw ShellCommandInstallError.writeFailed("The installed file could not be verified.")
            }
            return .success(())
        } catch {
            let command = elevatedInstallCommand(script: script, destination: destination)
            let result = await AppleScriptElevatedShellRunner().run(command)
            guard result.succeeded, isInstalled(appPath: appPath, at: destination) else {
                return .failure(
                    ShellCommandInstallError.authorizationFailed(
                        result.output.isEmpty ? "The installation was cancelled." : result.output
                    )
                )
            }
            return .success(())
        }
    }

    static func wrapperScript(appPath: String) -> String {
        let app = shellQuote(appPath)
        return """
        #!/bin/sh
        APP=\(app)

        if [ "$#" -eq 0 ]; then
            exec /usr/bin/open -a "$APP"
        fi

        case "$1" in
            -h|--help)
                printf '%s\\n' 'Usage: nodal [path ...]' '' \\
                    'Opens files or folders in Nodal IDE. With no paths, activates Nodal IDE.'
                exit 0
                ;;
            -v|--version)
                VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)
                printf '%s\\n' "${VERSION:-unknown}"
                exit 0
                ;;
            --)
                shift
                ;;
        esac

        if [ "$#" -eq 0 ]; then
            exec /usr/bin/open -a "$APP"
        fi

        exec /usr/bin/open -a "$APP" -- "$@"
        """
    }

    static func elevatedInstallCommand(script: String, destination: URL) -> String {
        let encoded = Data(script.utf8).base64EncodedString()
        let directory = destination.deletingLastPathComponent().path
        let path = shellQuote(destination.path)
        return [
            "/bin/mkdir -p \(shellQuote(directory))",
            "printf %s \(shellQuote(encoded)) | /usr/bin/base64 -D > \(path)",
            "/bin/chmod 755 \(path)"
        ].joined(separator: " && ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func write(
        _ script: String,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        do {
            try script.write(to: destination, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
        } catch {
            throw ShellCommandInstallError.writeFailed(error.localizedDescription)
        }
    }
}
