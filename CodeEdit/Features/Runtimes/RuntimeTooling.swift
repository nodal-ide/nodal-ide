//
//  RuntimeTooling.swift
//  CodeEdit
//
//  Detects the host tooling runtime installs depend on (Homebrew, developer tools, network).
//

import AppKit
import Combine
import Foundation

@MainActor
final class RuntimeTooling: ObservableObject {
    enum ToolStatus: Equatable {
        case unknown
        case available(path: String)
        case missing

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    @Published private(set) var brew: ToolStatus = .unknown
    @Published private(set) var developerTools: ToolStatus = .unknown
    @Published private(set) var hasNetwork: Bool = true
    @Published private(set) var isRefreshing = false

    var brewAvailable: Bool { brew.isAvailable }

    /// Re-detects the available tooling.
    func refresh() async {
        isRefreshing = true

        let brewPath = await run("command -v brew")
        let developerPath = await run("xcode-select -p 2>/dev/null")
        let network = await checkNetwork()

        brew = brewPath.isEmpty ? .missing : .available(path: brewPath)
        developerTools = developerPath.isEmpty ? .missing : .available(path: developerPath)
        hasNetwork = network
        isRefreshing = false
    }

    /// Opens the Homebrew installation instructions in the browser.
    func openHomebrewInstallPage() {
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }

    private func run(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: RuntimeShell.run(command))
            }
        }
    }

    private func checkNetwork() async -> Bool {
        guard let url = URL(string: "https://nodejs.org") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }
}
