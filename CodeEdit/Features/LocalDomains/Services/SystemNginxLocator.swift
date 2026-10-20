import Foundation

/// Locates a usable nginx binary and reads its version/prefix, caching nothing itself
/// (``LocalServerTooling`` owns caching).
@MainActor
final class SystemNginxLocator: NginxLocating {
    private static let candidatePaths = [
        "/opt/homebrew/bin/nginx",
        "/usr/local/bin/nginx"
    ]

    private let shell: any ShellRunning

    init(shell: any ShellRunning = SystemShellRunner()) {
        self.shell = shell
    }

    func locate() async -> NginxInstallation? {
        for path in Self.candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            if let installation = await inspect(URL(filePath: path)) {
                return installation
            }
        }

        let which = await shell.run("command -v nginx")
        guard which.succeeded, let path = Self.absolutePath(from: which.output) else {
            return nil
        }
        return await inspect(URL(filePath: path))
    }

    func inspect(_ executableURL: URL) async -> NginxInstallation? {
        let path = executableURL.path(percentEncoded: false)
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }

        let versionResult = await shell.run("\(Self.quote(path)) -v")
        guard versionResult.succeeded else {
            return nil
        }

        return NginxInstallation(
            executableURL: executableURL,
            version: Self.parseVersion(from: versionResult.output) ?? versionResult.output,
            prefixURL: await prefix(for: path)
        )
    }

    private func prefix(for executablePath: String) async -> URL? {
        let result = await shell.run("\(Self.quote(executablePath)) -V")
        guard result.succeeded else {
            return nil
        }
        guard let range = result.output.range(of: "--prefix=") else {
            return nil
        }

        let remainder = result.output[range.upperBound...]
        let value = remainder.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : URL(filePath: String(value))
    }

    private static func parseVersion(from output: String) -> String? {
        guard let marker = output.range(of: "nginx/") else {
            return nil
        }
        let version = output[marker.upperBound...].prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }

    private static func absolutePath(from output: String) -> String? {
        let candidates = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
        return candidates.first
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
