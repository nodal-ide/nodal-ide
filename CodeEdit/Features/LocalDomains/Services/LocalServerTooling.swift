import Foundation

enum LocalServerTool: String, CaseIterable, Identifiable {
    case nginx
    case mkcert
    case brew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nginx: return "nginx"
        case .mkcert: return "mkcert"
        case .brew: return "Homebrew"
        }
    }

    var brewFormula: String? {
        switch self {
        case .nginx: return "nginx"
        case .mkcert: return "mkcert"
        case .brew: return nil
        }
    }
}

struct LocalServerToolInstallation: Equatable, Sendable {
    let executableURL: URL
    let version: String
}

enum LocalServerToolStatus: Equatable, Sendable {
    case unknown
    case installed(LocalServerToolInstallation)
    case missing

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var version: String? {
        if case .installed(let installation) = self {
            return installation.version
        }
        return nil
    }
}

enum LocalServerToolingError: Error, Equatable, LocalizedError {
    case homebrewUnavailable
    case notInstallable(LocalServerTool)
    case installFailed(tool: LocalServerTool, output: String)

    var errorDescription: String? {
        switch self {
        case .homebrewUnavailable:
            return "Homebrew is required to install local development tools."
        case .notInstallable(let tool):
            return "\(tool.title) cannot be installed with Homebrew."
        case .installFailed(let tool, _):
            return "Installing \(tool.title) failed."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .homebrewUnavailable:
            return "Install Homebrew from brew.sh, then refresh."
        case .notInstallable:
            return "Install the tool manually, then refresh."
        case .installFailed(_, let output):
            return output.isEmpty ? "Check your network connection and try again." : output
        }
    }
}

/// Detects the host tools the local server depends on (nginx, mkcert, Homebrew), caches the result,
/// and can install missing tools through Homebrew.
@MainActor
final class LocalServerTooling: ObservableObject {
    @Published private(set) var nginx: LocalServerToolStatus = .unknown
    @Published private(set) var mkcert: LocalServerToolStatus = .unknown
    @Published private(set) var brew: LocalServerToolStatus = .unknown
    @Published private(set) var isRefreshing = false

    private let shell: any ShellRunning
    private let nginxLocator: any NginxLocating
    private var didProbe = false

    var brewAvailable: Bool {
        brew.isInstalled
    }

    init(shell: any ShellRunning, nginxLocator: any NginxLocating) {
        self.shell = shell
        self.nginxLocator = nginxLocator
    }

    convenience init() {
        self.init(shell: SystemShellRunner(), nginxLocator: SystemNginxLocator())
    }

    func status(for tool: LocalServerTool) -> LocalServerToolStatus {
        switch tool {
        case .nginx: return nginx
        case .mkcert: return mkcert
        case .brew: return brew
        }
    }

    /// Forgets the cached probe so the next ``refresh(force:)`` re-runs discovery.
    func invalidate() {
        didProbe = false
    }

    /// Runs discovery once; later calls are served from cache unless `force` is `true`.
    func refresh(force: Bool = false) async {
        guard force || !didProbe else {
            return
        }

        isRefreshing = true
        async let brewStatus = probeBrew()
        async let mkcertStatus = probeMkcert()
        async let nginxStatus = probeNginx()

        brew = await brewStatus
        mkcert = await mkcertStatus
        nginx = await nginxStatus
        isRefreshing = false
        didProbe = true
    }

    /// Installs `tool` through Homebrew, then refreshes just that tool's status.
    @discardableResult
    func install(_ tool: LocalServerTool) async throws -> LocalServerToolStatus {
        guard brew.isInstalled else {
            throw LocalServerToolingError.homebrewUnavailable
        }
        guard let formula = tool.brewFormula else {
            throw LocalServerToolingError.notInstallable(tool)
        }

        let result = await shell.run("brew install \(formula)")
        guard result.succeeded else {
            throw LocalServerToolingError.installFailed(tool: tool, output: result.output)
        }

        invalidate()
        await refresh(force: true)
        return status(for: tool)
    }

    private func probeBrew() async -> LocalServerToolStatus {
        let which = await shell.run("command -v brew")
        guard which.succeeded, let path = Self.absolutePath(from: which.output) else {
            return .missing
        }
        let version = await shell.run("brew --version")
        return .installed(
            LocalServerToolInstallation(
                executableURL: URL(filePath: path),
                version: Self.firstLine(version.output)
            )
        )
    }

    private func probeMkcert() async -> LocalServerToolStatus {
        let which = await shell.run("command -v mkcert")
        guard which.succeeded, let path = Self.absolutePath(from: which.output) else {
            return .missing
        }
        let version = await shell.run("mkcert -version")
        return .installed(
            LocalServerToolInstallation(
                executableURL: URL(filePath: path),
                version: Self.firstLine(version.output)
            )
        )
    }

    private func probeNginx() async -> LocalServerToolStatus {
        guard let installation = await nginxLocator.locate() else {
            return .missing
        }
        return .installed(
            LocalServerToolInstallation(
                executableURL: installation.executableURL,
                version: installation.version
            )
        )
    }

    private static func absolutePath(from output: String) -> String? {
        output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("/") }
    }

    private static func firstLine(_ output: String) -> String {
        output.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
