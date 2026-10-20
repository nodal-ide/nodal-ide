import Foundation

enum CertificateAuthorityStatus: Equatable, Sendable {
    case missing
    case present(trusted: Bool)

    var isTrusted: Bool {
        if case .present(true) = self {
            return true
        }
        return false
    }
}

struct SiteCertificate: Equatable, Sendable {
    let domain: SiteDomain
    let certificateURL: URL
    let privateKeyURL: URL
    let expiresAt: Date
}

@MainActor
protocol CertificateProviding: AnyObject {
    func authorityStatus() async -> CertificateAuthorityStatus
    func certificate(for domain: SiteDomain) async throws -> SiteCertificate
    func trustAuthority() async throws
    func resetAuthority() async throws
}
