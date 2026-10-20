import Foundation

struct NginxInstallation: Equatable, Sendable {
    let executableURL: URL
    let version: String
    let prefixURL: URL?
}

@MainActor
protocol NginxLocating: AnyObject {
    func locate() async -> NginxInstallation?
    func inspect(_ executableURL: URL) async -> NginxInstallation?
}
