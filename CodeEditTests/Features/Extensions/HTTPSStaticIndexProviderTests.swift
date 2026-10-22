@testable import CodeEdit
import CryptoKit
import Foundation
import Testing

@Suite(.serialized)
struct HTTPSStaticIndexProviderTests {
    @Test
    func fetchesCatalogAndReusesConditionalValidators() async throws {
        let catalog = testCatalog()
        let catalogData = try JSONEncoder().encode(catalog)
        let handler = StubHTTPResponse { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"catalog-v1\"" {
                return StubReply(statusCode: 304, headers: ["ETag": "\"catalog-v1\""])
            }
            return StubReply(headers: ["ETag": "\"catalog-v1\""], body: catalogData)
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
    func downloadsSameOriginPackageAndVerifiesDigest() async throws {
        let packageBytes = Data("package bytes".utf8)
        let digest = SHA256.hash(data: packageBytes).map { String(format: "%02x", $0) }.joined()
        let provider = makeProvider(handler: StubHTTPResponse { request in
            guard request.url?.absoluteString == "https://registry.example/packages/example.zip" else {
                return StubReply(statusCode: 404)
            }
            return StubReply(headers: ["Content-Type": "application/zip"], body: packageBytes)
        })
        let package = ExtensionCatalogVersion(
            url: URL(string: "packages/example.zip")!,
            integrity: digest,
            publishedAt: nil,
            nodal: nil
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = directory.appendingPathComponent("example.zip")
        defer { try? FileManager.default.removeItem(at: directory) }

        let downloaded = try await provider.download(
            package,
            from: testSource(),
            to: destination,
            progress: { _, _ in }
        )

        #expect(downloaded.fileURL == destination)
        #expect(downloaded.byteCount == Int64(packageBytes.count))
        #expect(try Data(contentsOf: destination) == packageBytes)
    }

    @Test
    func rejectsInvalidCatalogPackageDigestAndHTTPStatus() async throws {
        let invalidProvider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(body: Data("{invalid".utf8))
        })
        var rejectedCatalog = false
        do {
            _ = try await invalidProvider.refreshCatalog(for: testSource(), cached: nil)
        } catch ExtensionSourceProviderError.invalidResponse {
            rejectedCatalog = true
        }
        #expect(rejectedCatalog)

        let packageBytes = Data("package bytes".utf8)
        let packageProvider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(body: packageBytes)
        })
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

        let unavailableProvider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(statusCode: 503)
        })
        var rejectedStatus = false
        do {
            _ = try await unavailableProvider.refreshCatalog(for: testSource(), cached: nil)
        } catch let error as ExtensionSourceProviderError {
            rejectedStatus = error.isTransport
        }
        #expect(rejectedStatus)
    }

    @Test
    func rejectsNonHTTPSAndCrossOriginPackageURLs() async throws {
        let provider = makeProvider(handler: StubHTTPResponse { _ in StubReply() })
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

    @Test
    func rejectsCrossOriginRedirect() async throws {
        let catalogData = try JSONEncoder().encode(testCatalog())
        let provider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(
                headers: ["Content-Type": "application/json"],
                body: catalogData,
                finalURL: URL(string: "https://other.example/extensions.json")
            )
        })

        var rejectedRedirect = false
        do {
            _ = try await provider.refreshCatalog(for: testSource(), cached: nil)
        } catch ExtensionSourceProviderError.unsupportedRedirect {
            rejectedRedirect = true
        }
        #expect(rejectedRedirect)
    }

    @Test
    func rejectsOversizedCatalogAndPackage() async throws {
        let catalogProvider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(headers: [
                "Content-Length": "\(HTTPSStaticIndexProvider.maximumCatalogBytes + 1)"
            ])
        })
        var rejectedCatalog = false
        do {
            _ = try await catalogProvider.refreshCatalog(for: testSource(), cached: nil)
        } catch ExtensionSourceProviderError.responseTooLarge {
            rejectedCatalog = true
        }
        #expect(rejectedCatalog)

        let packageProvider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(headers: [
                "Content-Length": "\(HTTPSStaticIndexProvider.maximumPackageBytes + 1)"
            ])
        })
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("example.zip")
        var rejectedPackage = false
        do {
            _ = try await packageProvider.download(
                ExtensionCatalogVersion(
                    url: URL(string: "packages/example.zip")!,
                    integrity: String(repeating: "a", count: 64),
                    publishedAt: nil,
                    nodal: nil
                ),
                from: testSource(),
                to: destination,
                progress: { _, _ in }
            )
        } catch ExtensionSourceProviderError.responseTooLarge {
            rejectedPackage = true
        }
        #expect(rejectedPackage)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func mapsTransportFailureToError() async throws {
        let provider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(failure: URLError(.timedOut))
        })
        var rejectedTransport = false
        do {
            _ = try await provider.refreshCatalog(for: testSource(), cached: nil)
        } catch let error as ExtensionSourceProviderError {
            rejectedTransport = error.isTransport
        }
        #expect(rejectedTransport)
    }

    @Test
    func mapsCancellationToError() async throws {
        let provider = makeProvider(handler: StubHTTPResponse { _ in
            StubReply(hangForCancellation: true)
        })
        let task = Task {
            try await provider.refreshCatalog(for: testSource(), cached: nil)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        var cancelled = false
        do {
            _ = try await task.value
        } catch ExtensionSourceProviderError.cancelled {
            cancelled = true
        }
        #expect(cancelled)
    }
}

private extension HTTPSStaticIndexProviderTests {
    func makeProvider(handler: StubHTTPResponse) -> HTTPSStaticIndexProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.response = handler
        return HTTPSStaticIndexProvider(session: URLSession(configuration: configuration))
    }

    func testSource() -> ExtensionSource {
        ExtensionSource(
            name: "Fixture",
            providerID: .httpsStaticIndex,
            location: URL(string: "https://registry.example/extensions.json")!,
            isTrusted: true
        )
    }

    func testCatalog() -> ExtensionCatalog {
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

private struct StubReply {
    var statusCode = 200
    var headers: [String: String] = [:]
    var body = Data()
    var finalURL: URL?
    var failure: URLError?
    var hangForCancellation = false
}

private extension ExtensionSourceProviderError {
    var isTransport: Bool {
        if case .transport = self { return true }
        return false
    }
}

private final class StubHTTPResponse: @unchecked Sendable {
    private let lock = NSLock()
    private let response: (URLRequest) -> StubReply
    private var storedRequest: URLRequest?

    init(response: @escaping (URLRequest) -> StubReply) {
        self.response = response
    }

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func respond(to request: URLRequest) -> StubReply {
        lock.lock()
        storedRequest = request
        lock.unlock()
        return response(request)
    }
}

private class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: StubHTTPResponse?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let reply = Self.response?.respond(to: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        if reply.hangForCancellation {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            }
            return
        }
        guard let httpResponse = HTTPURLResponse(
            url: reply.finalURL ?? url,
            statusCode: reply.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
