import Foundation

enum LocalSiteRecoveryAction: String, Equatable, CaseIterable {
    case editDomain
    case editDocumentRoot
    case editEntryFile
    case installPHP
    case installNginx
    case trustCertificate
    case changePort
    case viewLogs
    case retry

    var title: String {
        switch self {
        case .editDomain: return "Edit Domain"
        case .editDocumentRoot: return "Choose Document Root"
        case .editEntryFile: return "Edit Entry File"
        case .installPHP: return "Install PHP"
        case .installNginx: return "Install nginx"
        case .trustCertificate: return "Trust Certificate"
        case .changePort: return "Change Port"
        case .viewLogs: return "View Logs"
        case .retry: return "Retry"
        }
    }
}

struct SiteValidationIssue: Equatable, Identifiable {
    enum Field: String, Equatable {
        case domain
        case documentRoot
        case entryFile
        case runtime
        case certificate
        case port
    }

    let field: Field
    let message: String
    let recoveryAction: LocalSiteRecoveryAction?

    var id: String { "\(field.rawValue):\(message)" }
}

enum LocalSiteError: Error, Equatable, LocalizedError {
    case invalidDomain(SiteDomainError)
    case domainInUse(String)
    case documentRootMissing(String)
    case documentRootOutsideWorkspace
    case entryFileMissing(String)
    case phpFPMUnavailable(String)
    case nginxUnavailable
    case certificateUntrusted
    case portInUse(Int)
    case upstreamNotReady(port: Int, output: String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDomain(let error):
            return error.errorDescription
        case .domainInUse(let domain):
            return "\(domain) is already used by another project."
        case .documentRootMissing(let path):
            return "The document root does not exist: \(path)."
        case .documentRootOutsideWorkspace:
            return "The document root must be inside the project."
        case .entryFileMissing(let path):
            return "The entry file does not exist: \(path)."
        case .phpFPMUnavailable(let version):
            return "PHP \(version) does not include PHP-FPM."
        case .nginxUnavailable:
            return "nginx is not installed."
        case .certificateUntrusted:
            return "The local certificate is not trusted."
        case .portInUse(let port):
            return "Port \(port) is already in use."
        case let .upstreamNotReady(port, output):
            var message = "The site's upstream did not start listening on port \(port)."
            if !output.isEmpty {
                message += "\n\n\(output)"
            }
            return message
        case .processFailed(let reason):
            return reason
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidDomain:
            return "Use a name ending in .localhost."
        case .domainInUse:
            return "Choose a different .localhost domain."
        case .documentRootMissing, .documentRootOutsideWorkspace:
            return "Choose a folder inside the project."
        case .entryFileMissing:
            return "Choose an entry file that exists."
        case .phpFPMUnavailable:
            return "Install a PHP runtime that includes PHP-FPM."
        case .nginxUnavailable:
            return "Install nginx with Homebrew."
        case .certificateUntrusted:
            return "Trust the CodeEdit local certificate."
        case .portInUse:
            return "Stop the other service or choose another port."
        case .upstreamNotReady:
            return "Check the start command and its output in the Tasks console."
        case .processFailed:
            return "Check the site log for details."
        }
    }

    var recoveryAction: LocalSiteRecoveryAction? {
        switch self {
        case .invalidDomain, .domainInUse:
            return .editDomain
        case .documentRootMissing, .documentRootOutsideWorkspace:
            return .editDocumentRoot
        case .entryFileMissing:
            return .editEntryFile
        case .phpFPMUnavailable:
            return .installPHP
        case .nginxUnavailable:
            return .installNginx
        case .certificateUntrusted:
            return .trustCertificate
        case .portInUse:
            return .changePort
        case .upstreamNotReady:
            return .viewLogs
        case .processFailed:
            return .viewLogs
        }
    }
}
