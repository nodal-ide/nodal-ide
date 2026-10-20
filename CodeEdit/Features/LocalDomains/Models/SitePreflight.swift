import Foundation

enum SitePreflightKind: String, CaseIterable, Identifiable {
    case nginx
    case mkcert
    case phpFPM
    case certificate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nginx: return "nginx"
        case .mkcert: return "mkcert"
        case .phpFPM: return "PHP-FPM"
        case .certificate: return "Certificate Authority"
        }
    }

    var systemImage: String {
        switch self {
        case .nginx: return "server.rack"
        case .mkcert: return "key.horizontal.fill"
        case .phpFPM: return "p.circle.fill"
        case .certificate: return "checkmark.seal.fill"
        }
    }
}

enum SitePreflightStatus: Equatable {
    case checking
    case ready(String)
    case actionRequired(String)
    case skipped(String)

    var isActionRequired: Bool {
        if case .actionRequired = self {
            return true
        }
        return false
    }
}

struct SitePreflightItem: Identifiable, Equatable {
    let kind: SitePreflightKind
    let status: SitePreflightStatus

    var id: String { kind.rawValue }
}

/// Pure checklist assembly for the Local Domain page. Each dependency reports whether it is ready,
/// needs an action, or is unnecessary for the current settings.
struct SitePreflightInputs {
    let nginx: LocalServerToolStatus
    let mkcert: LocalServerToolStatus
    let phpRuntimes: [LocalSiteRuntime]
    let pinnedPHP: String?
    let authority: CertificateAuthorityStatus
    let usesHTTPS: Bool
}

enum SitePreflight {
    static func items(_ inputs: SitePreflightInputs) -> [SitePreflightItem] {
        [
            SitePreflightItem(kind: .nginx, status: toolStatus(inputs.nginx, name: "nginx")),
            SitePreflightItem(kind: .mkcert, status: toolStatus(inputs.mkcert, name: "mkcert")),
            SitePreflightItem(
                kind: .phpFPM,
                status: phpStatus(runtimes: inputs.phpRuntimes, pinned: inputs.pinnedPHP)
            ),
            SitePreflightItem(
                kind: .certificate,
                status: certificateStatus(authority: inputs.authority, usesHTTPS: inputs.usesHTTPS)
            )
        ]
    }

    private static func toolStatus(
        _ status: LocalServerToolStatus,
        name: String
    ) -> SitePreflightStatus {
        switch status {
        case .unknown:
            return .checking
        case .missing:
            return .actionRequired("\(name) is required and was not found.")
        case .installed(let installation):
            let version = installation.version.trimmingCharacters(in: .whitespacesAndNewlines)
            return .ready(version.isEmpty ? "\(name) is installed." : "\(name) \(version)")
        }
    }

    private static func phpStatus(runtimes: [LocalSiteRuntime], pinned: String?) -> SitePreflightStatus {
        if let pinned, !pinned.isEmpty {
            guard runtimes.contains(where: { $0.version == pinned }) else {
                return .actionRequired("PHP \(pinned) has no PHP-FPM. Install it or choose another version.")
            }
            return .ready("PHP \(pinned) with PHP-FPM")
        }
        guard let newest = runtimes.first else {
            return .actionRequired("No installed PHP runtime includes PHP-FPM.")
        }
        return .ready("PHP \(newest.version) with PHP-FPM")
    }

    private static func certificateStatus(
        authority: CertificateAuthorityStatus,
        usesHTTPS: Bool
    ) -> SitePreflightStatus {
        guard usesHTTPS else {
            return .skipped("HTTPS is off; the site will be served over HTTP.")
        }
        switch authority {
        case .present(trusted: true):
            return .ready("The local certificate authority is trusted.")
        case .present(trusted: false):
            return .actionRequired("Trust the CodeEdit certificate authority to enable HTTPS.")
        case .missing:
            return .actionRequired("Create and trust the CodeEdit certificate authority.")
        }
    }
}
