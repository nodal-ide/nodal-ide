@testable import CodeEdit
import CryptoKit
import Foundation
import Testing

@Suite
struct HTTPSStaticIndexProviderTests {
    @Test
    func fetchesCatalogAndReusesConditionalValidators() async throws {
        let catalog = testCatalog()
        let catalogData = try JSONEncoder().encode(catalog)
        let handler = StubHTTPResponse { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"catalog-v1\"" {
                return (304, ["ETag": "\"catalog-v1\""], Data())
            }
            return (200, ["ETag": "\"catalog-v1\""], catalogData)
        }
        let provider = makeProvider(handler: handler)
        let source = testSource()

        let first = try await provider.refreshCatalog(for: source, cached: nil)
        let cached = CachedExtensionCatalog(
            catalog: first.catalog,
            fetchedAt: Date(timeIntervalSince1970: 1),
            entityTag: first.entityTag,
            lastModified: first.lastModified
        )
        let second = try await provider.refreshCatalog(for: source, cached: cached)

        #expect(first.catalog == catalog)
        #expect(first.entityTag == "\"catalog-v1\"")
        #expect(second.notModified)
        #expect(handler.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == "\"catalog-v1\"")
    }

    @Test
    func rejectsInvalidCatalogAndPackageDigest() async throws {
        let invalidProvider = makeProvider(handler: StubHTTPResponse { _ in
            (200, [:], Data("{invalid".utf8))
        })
        var rejectedCatalog = false
        do {
            _ = try await invalidProvider.refreshCatalog(for: testSource(), cached: nil)
        } catch ExtensionSourceProviderError.invalidResponse {
            rejectedCatalog = true
        }
        #expect(rejectedCatalog)

        let packageBytes = Data("package bytes".utf8)
        let packageProvider = makeProvider(handler: StubHTTPResponse { _ in (200, [:], packageBytes) })
        let package = ExtensionCatalogVersion(
            url: URL(string: "packages/example.zip")!,
            integrity: String(repeating: "0", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("example.zip")
        var rejectedDigest = false
        do {
            _ = try await packageProvider.download(
                package,
                from: testSource(),
                to: destination,
                progress: { _, _ in }
            )
        } catch ExtensionSourceProviderError.integrityMismatch {
            rejectedDigest = true
        }
        #expect(rejectedDigest)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rejectsNonHTTPSAndCrossOriginPackageURLs() async throws {
        let provider = makeProvider(handler: StubHTTPResponse { _ in (200, [:], Data()) })
        let insecure = ExtensionSource(
            name: "Insecure",
            providerID: .httpsStaticIndex,
            location: URL(string: "http://registry.example/extensions.json")!
        )
        var rejectedSource = false
        do {
            try await provider.validate(insecure)
        } catch ExtensionSourceProviderError.invalidConfiguration {
            rejectedSource = true
        }
        #expect(rejectedSource)

        let crossOrigin = ExtensionCatalogVersion(
            url: URL(string: "https://other.example/package.zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        var rejectedPackage = false
        do {
            _ = try await provider.download(
                crossOrigin,
                from: testSource(),
                to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                progress: { _, _ in }
            )
        } catch ExtensionSourceProviderError.invalidConfiguration {
            rejectedPackage = true
        }
        #expect(rejectedPackage)
    }

    private func makeProvider(handler: StubHTTPResponse) -> HTTPSStaticIndexProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.response = handler
        return HTTPSStaticIndexProvider(session: URLSession(configuration: configuration))
    }

    private func testSource() -> ExtensionSource {
        ExtensionSource(
            name: "Fixture",
            providerID: .httpsStaticIndex,
            location: URL(string: "https://registry.example/extensions.json")!,
            isTrusted: true
        )
    }

    private func testCatalog() -> ExtensionCatalog {
        let version = ExtensionCatalogVersion(
            url: URL(string: "packages/example.zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        let entry = ExtensionCatalogEntry(
            name: "Example",
            description: "Fixture extension",
            publisher: "Tests",
            url: nil,
            latest: "1.0.0",
            versions: ["1.0.0": version]
        )
        return ExtensionCatalog(schemaVersion: 1, extensions: ["com.example.fixture": entry])
    }
}

private final class StubHTTPResponse: @unchecked Sendable {
    private let lock = NSLock()
    private let response: (URLRequest) -> (Int, [String: String], Data)
    private var storedRequest: URLRequest?

    init(response: @escaping (URLRequest) -> (Int, [String: String], Data)) {
        self.response = response
    }

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func respond(to request: URLRequest) -> (Int, [String: String], Data) {
        lock.lock()
        storedRequest = request
        lock.unlock()
        return response(request)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: StubHTTPResponse?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response?.respond(to: request),
              let url = request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.0,
                httpVersion: "HTTP/1.1",
                headerFields: response.1
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if !response.2.isEmpty {
            client?.urlProtocol(self, didLoad: response.2)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
