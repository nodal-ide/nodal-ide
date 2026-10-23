@testable import CodeEdit
import Foundation
import Testing

@Suite
struct AssistantEndpointTests {
    @Test
    func httpsBaseGetsVersionPath() throws {
        let endpoint = try AssistantEndpoint(
            baseURLString: " https://example.com/ ",
            allowInsecureHTTP: false
        )

        #expect(endpoint.baseURL.absoluteString == "https://example.com/v1")
        #expect(endpoint.chatCompletionsURL.absoluteString == "https://example.com/v1/chat/completions")
        #expect(endpoint.modelsURL.absoluteString == "https://example.com/v1/models")
        #expect(!endpoint.isLoopback)
    }

    @Test
    func existingVersionAndPathPrefixArePreserved() throws {
        let endpoint = try AssistantEndpoint(
            baseURLString: "https://example.com/openai/v1/",
            allowInsecureHTTP: false
        )
        let prefixed = try AssistantEndpoint(
            baseURLString: "https://example.com/openai",
            allowInsecureHTTP: false
        )

        #expect(endpoint.baseURL.absoluteString == "https://example.com/openai/v1")
        #expect(prefixed.baseURL.absoluteString == "https://example.com/openai/v1")
        #expect(endpoint.displayHost == "example.com")
    }

    @Test
    func loopbackHTTPIsAllowedWithoutOptIn() throws {
        let localhost = try AssistantEndpoint(
            baseURLString: "http://localhost:1234",
            allowInsecureHTTP: false
        )
        let ipv4 = try AssistantEndpoint(
            baseURLString: "http://127.0.0.1:1234/v1",
            allowInsecureHTTP: false
        )
        let ipv6 = try AssistantEndpoint(
            baseURLString: "http://[::1]:1234/v1",
            allowInsecureHTTP: false
        )

        #expect(localhost.isLoopback)
        #expect(ipv4.isLoopback)
        #expect(ipv6.isLoopback)
        #expect(ipv4.displayHost == "127.0.0.1:1234")
        #expect(ipv6.displayHost == "[::1]:1234")
    }

    @Test
    func remoteHTTPRequiresExplicitOptIn() throws {
        do {
            _ = try AssistantEndpoint(
                baseURLString: "http://example.com/v1",
                allowInsecureHTTP: false
            )
            Issue.record("Expected remote HTTP to be rejected.")
        } catch let error as AssistantEndpointError {
            #expect(error == .insecureHTTP)
        }

        let optedIn = try AssistantEndpoint(
            baseURLString: "http://example.com/v1",
            allowInsecureHTTP: true
        )
        #expect(!optedIn.isLoopback)
    }

    @Test
    func loopbackLookalikeHostsAreNotTreatedAsLocal() {
        expectError(.insecureHTTP, url: "http://127.evil.com/v1")
        expectError(.insecureHTTP, url: "http://127.0.0.1.evil.com/v1")
        expectError(.insecureHTTP, url: "http://127.0.0.999/v1")
    }

    @Test
    func credentialAndQueryURLsAreRejected() {
        expectError(.embeddedCredentials, url: "https://user:pass@example.com/v1")
        expectError(.queryOrFragment, url: "https://example.com/v1?token=secret")
        expectError(.queryOrFragment, url: "https://example.com/v1#fragment")
    }

    @Test
    func invalidSchemesAndFullEndpointsAreRejected() {
        expectError(.unsupportedScheme, url: "ftp://example.com/v1")
        expectError(.invalidURL, url: "")
        expectError(.fullEndpointPath, url: "https://example.com/v1/chat/completions")
        expectError(.fullEndpointPath, url: "https://example.com/v1/models")
    }

    private func expectError(
        _ expected: AssistantEndpointError,
        url: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try AssistantEndpoint(baseURLString: url, allowInsecureHTTP: false)
            Issue.record("Expected \(expected) for \(url).", sourceLocation: sourceLocation)
        } catch let error as AssistantEndpointError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error \(error) for \(url).", sourceLocation: sourceLocation)
        }
    }
}
