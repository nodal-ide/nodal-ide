import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct SiteRegistryTests {
    private func makeRegistration(
        siteID: String,
        domain: String,
        path: String
    ) throws -> SiteRegistration {
        SiteRegistration(
            siteID: siteID,
            domain: try SiteDomain(domain),
            workspaceURL: URL(filePath: path)
        )
    }

    @Test
    func registersAndLooksUpSites() throws {
        let registry = SiteRegistry()
        let registration = try makeRegistration(siteID: "site-a", domain: "app", path: "/tmp/a")

        try registry.register(registration)

        #expect(registry.count == 1)
        #expect(registry.registration(for: registration.domain) == registration)
        #expect(registry.registration(forSiteID: "site-a") == registration)
        #expect(registry.owner(of: registration.domain) == registration)
    }

    @Test
    func rejectsDuplicateDomainAndReportsOwner() throws {
        let registry = SiteRegistry()
        let first = try makeRegistration(siteID: "site-a", domain: "app", path: "/tmp/a")
        let second = try makeRegistration(siteID: "site-b", domain: "app", path: "/tmp/b")

        try registry.register(first)

        do {
            try registry.register(second)
            Issue.record("Expected the duplicate domain to be rejected.")
        } catch let error as SiteRegistryError {
            #expect(error == .domainInUse(domain: first.domain, owner: first))
        }

        #expect(registry.count == 1)
        #expect(registry.registration(forSiteID: "site-b") == nil)
    }

    @Test
    func reRegisteringSameSiteIsIdempotent() throws {
        let registry = SiteRegistry()
        let registration = try makeRegistration(siteID: "site-a", domain: "app", path: "/tmp/a")

        try registry.register(registration)
        try registry.register(registration)

        #expect(registry.count == 1)
        #expect(registry.registration(for: registration.domain) == registration)
    }

    @Test
    func reRegisteringSiteWithNewDomainMovesRegistration() throws {
        let registry = SiteRegistry()
        let original = try makeRegistration(siteID: "site-a", domain: "app", path: "/tmp/a")
        let moved = try makeRegistration(siteID: "site-a", domain: "renamed", path: "/tmp/a")

        try registry.register(original)
        try registry.register(moved)

        #expect(registry.count == 1)
        #expect(registry.registration(for: original.domain) == nil)
        #expect(registry.registration(for: moved.domain) == moved)
        #expect(registry.registration(forSiteID: "site-a") == moved)
    }

    @Test
    func movingSiteOntoOccupiedDomainIsRejected() throws {
        let registry = SiteRegistry()
        let first = try makeRegistration(siteID: "site-a", domain: "app", path: "/tmp/a")
        let second = try makeRegistration(siteID: "site-b", domain: "other", path: "/tmp/b")

        try registry.register(first)
        try registry.register(second)

        do {
            try registry.register(
                try makeRegistration(siteID: "site-b", domain: "app", path: "/tmp/b")
            )
            Issue.record("Expected the move onto an occupied domain to be rejected.")
        } catch let error as SiteRegistryError {
            #expect(error == .domainInUse(domain: first.domain, owner: first))
        }

        #expect(registry.count == 2)
        #expect(registry.registration(for: first.domain) == first)
        #expect(registry.registration(for: second.domain) == second)
    }

    @Test
    func unregistersByDomainAndSiteID() throws {
        let registry = SiteRegistry()
        let first = try makeRegistration(siteID: "site-a", domain: "app", path: "/tmp/a")
        let second = try makeRegistration(siteID: "site-b", domain: "other", path: "/tmp/b")

        try registry.register(first)
        try registry.register(second)

        #expect(registry.unregister(domain: first.domain) == first)
        #expect(registry.registration(forSiteID: "site-a") == nil)
        #expect(registry.unregister(siteID: "site-b") == second)
        #expect(registry.registration(for: second.domain) == nil)
        #expect(registry.isEmpty)

        #expect(registry.unregister(domain: first.domain) == nil)
        #expect(registry.unregister(siteID: "site-a") == nil)
    }

    @Test
    func derivesStableSiteIDFromWorkspaceURL() throws {
        let url = URL(filePath: "/tmp/example/")
        let withTrailingSlash = URL(filePath: "/tmp/example")

        #expect(SiteRegistration.siteID(forWorkspaceURL: url)
            == SiteRegistration.siteID(forWorkspaceURL: withTrailingSlash))
    }
}
