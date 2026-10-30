import Foundation

struct CertificateAuthorityPaths: Equatable, Sendable {
    let root: URL
    let certificates: URL

    static var `default`: CertificateAuthorityPaths {
        let proxy = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".nodalide", directoryHint: .isDirectory)
            .appending(path: "proxy", directoryHint: .isDirectory)
        return CertificateAuthorityPaths(
            root: proxy.appending(path: "ca", directoryHint: .isDirectory),
            certificates: proxy.appending(path: "certs", directoryHint: .isDirectory)
        )
    }

    /// mkcert's `CAROOT` root certificate/key (the `CAROOT` env var points at ``root``).
    var rootCertificate: URL {
        root.appending(path: "rootCA.pem")
    }

    var rootKey: URL {
        root.appending(path: "rootCA-key.pem")
    }

    func certificate(for domain: String) -> URL {
        certificates.appending(path: "\(domain).pem")
    }

    func privateKey(for domain: String) -> URL {
        certificates.appending(path: "\(domain)-key.pem")
    }

    func metadata(for domain: String) -> URL {
        certificates.appending(path: "\(domain).json")
    }
}

struct SiteCertificateMetadata: Codable, Equatable, Sendable {
    let domains: [String]
    let notAfter: Date
    let authorityFingerprint: String
}

enum CertificateAuthorityError: Error, Equatable, LocalizedError {
    case mkcertUnavailable
    case installFailed(String)
    case issuanceFailed(String)
    case inspectionFailed(String)
    case trustCancelled
    case trustFailed(String)
    case resetFailed(String)

    var errorDescription: String? {
        switch self {
        case .mkcertUnavailable:
            return "mkcert is not installed."
        case .installFailed(let message):
            return "Could not install mkcert: \(message)"
        case .issuanceFailed(let message):
            return "Could not create a certificate: \(message)"
        case .inspectionFailed(let message):
            return "Could not read the created certificate: \(message)"
        case .trustCancelled:
            return "Trusting the certificate authority was cancelled."
        case .trustFailed(let message):
            return "The certificate authority could not be trusted: \(message)"
        case .resetFailed(let message):
            return "The certificate authority could not be removed: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .trustCancelled:
            return "The site can still run over HTTP; trust the authority later to enable HTTPS."
        case .trustFailed, .resetFailed:
            return "Allow the security prompt, or trust the mkcert development CA in Keychain Access manually."
        case .mkcertUnavailable:
            return "Install mkcert from the Local Domain preflight checklist."
        case .installFailed, .issuanceFailed, .inspectionFailed:
            return nil
        }
    }
}
