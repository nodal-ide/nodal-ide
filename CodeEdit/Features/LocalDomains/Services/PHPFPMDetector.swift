import Foundation

struct PHPFPMInstallation: Equatable, Sendable {
    let executableURL: URL
    let version: String
}

enum PHPFPMStatus: Equatable, Sendable {
    /// nginx-compatible php-fpm found in the same install as the selected PHP, with a matching version.
    case available(PHPFPMInstallation)
    /// No php-fpm next to the runtime and none on `PATH`.
    case missing
    /// A php-fpm exists but belongs to a different PHP version; never mix them.
    case versionMismatch(expected: String, found: String)
    /// A php-fpm executable exists but did not report a PHP version.
    case unusable(URL)

    var installation: PHPFPMInstallation? {
        if case .available(let installation) = self {
            return installation
        }
        return nil
    }

    var isAvailable: Bool {
        installation != nil
    }

    /// Short label for a runtime row badge.
    var badgeText: String {
        switch self {
        case .available:
            return "FPM"
        case .versionMismatch(_, let found):
            return "FPM \(found)"
        case .missing, .unusable:
            return "No FPM"
        }
    }

    /// A full explanation, suitable for a tooltip.
    var detail: String {
        switch self {
        case .available(let installation):
            return "PHP-FPM \(installation.version) available"
        case .missing:
            return "No php-fpm found for this PHP version"
        case let .versionMismatch(expected, found):
            return "php-fpm \(found) does not match PHP \(expected)"
        case .unusable(let url):
            return "\(url.lastPathComponent) does not report a PHP version"
        }
    }
}

/// Detects the `php-fpm` companion for a PHP runtime. Abstracted so callers can supply a fake.
@MainActor
protocol PHPFPMDetecting: AnyObject {
    func status(for runtime: InstalledRuntime) async -> PHPFPMStatus
}

/// Detects the `php-fpm` companion for a selected PHP runtime. FPM is a capability of an installed
/// runtime (not a separate ``RuntimeKind``): it is looked up as `../sbin/php-fpm` next to `bin/php`,
/// with a `PATH` fallback, and its version must match the interpreter's major.minor.
@MainActor
final class PHPFPMDetector: PHPFPMDetecting {
    private let shell: any ShellRunning

    init(shell: any ShellRunning = SystemShellRunner()) {
        self.shell = shell
    }

    func status(for runtime: InstalledRuntime) async -> PHPFPMStatus {
        let sibling = await probe(runtime.executable(relativePath: "sbin/php-fpm"))
        switch sibling {
        case .available(let installation):
            guard Self.matches(runtime.version, installation.version) else {
                return .versionMismatch(expected: runtime.version, found: installation.version)
            }
            return .available(installation)
        case .unusable:
            return sibling
        case .missing, .versionMismatch:
            break
        }

        let which = await shell.run("command -v php-fpm")
        guard which.succeeded, let path = Self.absolutePath(from: which.output) else {
            return .missing
        }

        let fallback = await probe(URL(filePath: path))
        guard case let .available(installation) = fallback else {
            return fallback
        }
        guard Self.matches(runtime.version, installation.version) else {
            return .versionMismatch(expected: runtime.version, found: installation.version)
        }
        return .available(installation)
    }

    /// The installation when available, otherwise `nil`.
    func installation(for runtime: InstalledRuntime) async -> PHPFPMInstallation? {
        await status(for: runtime).installation
    }

    // MARK: - Probing

    private func probe(_ url: URL) async -> PHPFPMStatus {
        guard FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) else {
            return .missing
        }
        let result = await shell.run("\(Self.quote(url.path(percentEncoded: false))) -v")
        guard let version = Self.parseVersion(from: result.output) else {
            return .unusable(url)
        }
        return .available(PHPFPMInstallation(executableURL: url, version: version))
    }

    // MARK: - Parsing

    /// Extracts the version from `php-fpm -v` output (`PHP 8.4.12 (fpm-fcgi)`).
    static func parseVersion(from output: String) -> String? {
        guard let range = output.range(of: "PHP ") else {
            return nil
        }
        let version = output[range.upperBound...].prefix { $0.isNumber || $0 == "." }
        let value = String(version)
        return value.isEmpty ? nil : value
    }

    /// Compares major.minor, so patch differences within one install are accepted.
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        minor(lhs) == minor(rhs)
    }

    private static func minor(_ version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    private static func absolutePath(from output: String) -> String? {
        output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("/") }
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
