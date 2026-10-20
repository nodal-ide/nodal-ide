import Foundation

struct SiteRegistration: Equatable, Sendable {
    let siteID: String
    let domain: SiteDomain
    let workspaceURL: URL

    init(siteID: String, domain: SiteDomain, workspaceURL: URL) {
        self.siteID = siteID
        self.domain = domain
        self.workspaceURL = workspaceURL
    }

    init(workspaceURL: URL, domain: SiteDomain) {
        self.init(
            siteID: SiteRegistration.siteID(forWorkspaceURL: workspaceURL),
            domain: domain,
            workspaceURL: workspaceURL
        )
    }

    static func siteID(forWorkspaceURL url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path.sha256()
    }
}

enum SiteRegistryError: Error, Equatable, LocalizedError {
    case domainInUse(domain: SiteDomain, owner: SiteRegistration)

    var errorDescription: String? {
        switch self {
        case .domainInUse(let domain, _):
            return "\(domain.value) is already used by another project."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .domainInUse:
            return "Choose a different .localhost domain."
        }
    }

    var recoveryAction: LocalSiteRecoveryAction? {
        switch self {
        case .domainInUse:
            return .editDomain
        }
    }
}

@MainActor
final class SiteRegistry {
    private var registrationsByDomain: [SiteDomain: SiteRegistration] = [:]
    private var registrationsBySiteID: [String: SiteRegistration] = [:]

    var count: Int {
        registrationsByDomain.count
    }

    var isEmpty: Bool {
        registrationsByDomain.isEmpty
    }

    var registrations: [SiteRegistration] {
        Array(registrationsByDomain.values)
    }

    @discardableResult
    func register(_ registration: SiteRegistration) throws -> SiteRegistration {
        if let existing = registrationsByDomain[registration.domain] {
            guard existing.siteID == registration.siteID else {
                throw SiteRegistryError.domainInUse(domain: registration.domain, owner: existing)
            }
        }

        if let existing = registrationsBySiteID[registration.siteID], existing.domain != registration.domain {
            registrationsByDomain[existing.domain] = nil
        }

        registrationsByDomain[registration.domain] = registration
        registrationsBySiteID[registration.siteID] = registration
        return registration
    }

    func registration(for domain: SiteDomain) -> SiteRegistration? {
        registrationsByDomain[domain]
    }

    func registration(forSiteID siteID: String) -> SiteRegistration? {
        registrationsBySiteID[siteID]
    }

    func owner(of domain: SiteDomain) -> SiteRegistration? {
        registrationsByDomain[domain]
    }

    @discardableResult
    func unregister(domain: SiteDomain) -> SiteRegistration? {
        guard let registration = registrationsByDomain.removeValue(forKey: domain) else {
            return nil
        }
        registrationsBySiteID[registration.siteID] = nil
        return registration
    }

    @discardableResult
    func unregister(siteID: String) -> SiteRegistration? {
        guard let registration = registrationsBySiteID.removeValue(forKey: siteID) else {
            return nil
        }
        registrationsByDomain[registration.domain] = nil
        return registration
    }

    func removeAll() {
        registrationsByDomain.removeAll()
        registrationsBySiteID.removeAll()
    }
}
