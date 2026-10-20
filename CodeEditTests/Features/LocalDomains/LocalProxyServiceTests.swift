import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct LocalProxyServiceTests {
    @Test
    func prepareAcquiresTheLockAndIsIdempotent() throws {
        try withTempDir { directory in
            let lock = LocalProxyLock(lockFileURL: directory.appending(path: "lock"))
            let service = LocalProxyService(lock: lock)

            try service.prepare()
            try service.prepare()

            #expect(lock.isHeld)
        }
    }

    @Test
    func terminateReleasesTheLockAndClearsTheRegistry() async throws {
        try await withTempDir { directory in
            let lock = LocalProxyLock(lockFileURL: directory.appending(path: "lock"))
            let service = LocalProxyService(lock: lock)
            try service.prepare()
            try service.registry.register(
                SiteRegistration(siteID: "site-a", domain: try SiteDomain("app"), workspaceURL: directory)
            )
            #expect(service.registry.count == 1)

            await service.terminate()

            #expect(!lock.isHeld)
            #expect(service.registry.isEmpty)
        }
    }

    @Test
    func makeOperationsReturnsTheSitePipeline() {
        let service = LocalProxyService(lock: LocalProxyLock(lockFileURL: URL(filePath: "/tmp/unused-lock")))

        let operations = service.makeOperations(
            workspaceURL: URL(filePath: "/tmp/project"),
            site: { LocalSiteSettings() }
        )

        #expect(operations is SitePipelineOperations)
    }
}
