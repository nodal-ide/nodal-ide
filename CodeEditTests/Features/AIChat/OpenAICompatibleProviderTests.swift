@testable import CodeEdit
import Foundation
import Testing

@Suite(.serialized)
struct OpenAICompatibleProviderTests { // swiftlint:disable:this type_body_length
    @Test
    func streamsSplitSSEEventsAndSendsAuth() async throws {
        let secondEvent = Data("data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n".utf8)
        let split = secondEvent.index(secondEvent.startIndex, offsetBy: 21)
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "text/event-stream"],
                chunks: [
                    Data("data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n".utf8),
                    Data(": keepalive\n\n".utf8),
                    secondEvent[..<split],
                    secondEvent[split...],
                    Data("data: [DONE]\n\n".utf8)
                ]
            )
        }
        let provider = try makeProvider()
        let events = try await collect(provider)

        #expect(events == [.delta("Hel"), .delta("lo"), .completed])
        let request = try #require(AssistantStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test
    func remoteEndpointRequiresContextConsentRegardlessOfLocalFlag() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "text/event-stream"],
                chunks: [Data("data: [DONE]\n\n".utf8)]
            )
        }
        let profile = AssistantProviderProfile(
            name: "Remote",
            baseURL: "https://api.example.com/v1",
            model: "test-model",
            isLocal: true
        )
        let provider = try OpenAICompatibleProvider(
            profile: profile,
            apiKey: "secret",
            settings: AssistantSettings(),
            session: makeSession()
        )
        let context = AssistantContextPacket(
            items: [
                AssistantContextItem(
                    id: "active",
                    kind: .activeFile,
                    title: "File.swift",
                    text: "let value = 1"
                )
            ],
            estimatedTokens: 5,
            warnings: [],
            omittedTitles: []
        )
        let request = AssistantRequest(
            prompt: "Explain",
            conversation: [AssistantMessage(role: .user, content: "Explain")],
            systemInstructions: "System",
            context: context
        )

        do {
            for try await _ in provider.stream(request) {}
            Issue.record("Expected remote context consent error.")
        } catch let error as AssistantProviderError {
            #expect(error == .remoteContextConsentRequired(host: "api.example.com"))
        }
    }

    @Test
    func requestPayloadIncludesSamplingAndConversation() throws {
        let profile = localProfile()
        var settings = AssistantSettings()
        settings.temperature = 0.7
        settings.maxOutputTokens = 1_024
        let request = AssistantRequest(
            prompt: "Explain",
            conversation: [AssistantMessage(role: .user, content: "Explain")],
            systemInstructions: "Be precise.",
            context: nil
        )
        let data = try JSONEncoder().encode(
            ChatRequestPayload(request: request, profile: profile, settings: settings, stream: true)
        )
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])

        #expect(json["model"] as? String == "test-model")
        #expect(json["stream"] as? Bool == true)
        #expect(json["temperature"] as? Double == 0.7)
        #expect(json["max_tokens"] as? Int == 1_024)
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.first?["content"] as? String == "Be precise.")
        #expect(messages.last?["role"] as? String == "user")
        #expect(messages.last?["content"] as? String == "Explain")
        #expect(messages.filter { $0["role"] as? String == "user" }.count == 1)
    }

    @Test
    func compatibilityModeOmitsSamplingFields() throws {
        var profile = localProfile()
        profile.compatibilityMode = true
        let request = AssistantRequest(prompt: "Hello", conversation: [], systemInstructions: nil, context: nil)
        let data = try JSONEncoder().encode(
            ChatRequestPayload(request: request, profile: profile, settings: AssistantSettings(), stream: true)
        )
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["temperature"] == nil)
        #expect(json["max_tokens"] == nil)
        #expect(json["stream"] as? Bool == true)
    }

    @Test
    func nonStreamingResponseYieldsWholeMessage() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "application/json"],
                chunks: [
                    Data("{\"choices\":[{\"message\":{\"content\":\"Complete answer\"}}]}".utf8)
                ]
            )
        }
        var settings = AssistantSettings()
        settings.streamResponses = false
        let provider = try makeProvider(settings: settings)
        let events = try await collect(provider)

        #expect(events == [.delta("Complete answer"), .completed])
        let request = try #require(AssistantStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test
    func unauthorizedResponseIsActionable() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                chunks: [Data("{\"error\":{\"message\":\"invalid key\"}}".utf8)]
            )
        }
        let provider = try makeProvider()

        do {
            _ = try await collect(provider)
            Issue.record("Expected unauthorized error.")
        } catch let error as AssistantProviderError {
            #expect(error == .unauthorized)
        }
    }

    @Test
    func rateLimitUsesRetryAfter() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                statusCode: 429,
                headers: [
                    "Content-Type": "application/json",
                    "Retry-After": "7"
                ],
                chunks: [Data("{\"error\":{\"message\":\"slow down\"}}".utf8)]
            )
        }
        let provider = try makeProvider()

        do {
            _ = try await collect(provider)
            Issue.record("Expected rate-limit error.")
        } catch let error as AssistantProviderError {
            #expect(error == .rateLimited(retryAfter: 7))
        }
    }

    @Test
    func reasoningOnlyStreamIsActionable() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "text/event-stream"],
                chunks: [
                    Data("data: {\"choices\":[{\"delta\":{\"reasoning\":\"Thinking\"}}]}\n\n".utf8),
                    Data("data: [DONE]\n\n".utf8)
                ]
            )
        }
        let provider = try makeProvider()

        do {
            _ = try await collect(provider)
            Issue.record("Expected reasoning-only error.")
        } catch let error as AssistantProviderError {
            #expect(error == .reasoningOnlyResponse)
        }
    }

    @Test
    func malformedEventFailsStream() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "text/event-stream"],
                chunks: [Data("data: not-json\n\n".utf8)]
            )
        }
        let provider = try makeProvider()

        do {
            _ = try await collect(provider)
            Issue.record("Expected malformed stream error.")
        } catch let error as AssistantProviderError {
            #expect(error == .malformedStream)
        }
    }

    @Test
    func jsonResponseToStreamingRequestIsRejected() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "application/json"],
                chunks: [Data("{}".utf8)]
            )
        }
        let provider = try makeProvider()

        do {
            _ = try await collect(provider)
            Issue.record("Expected unsupported stream error.")
        } catch let error as AssistantProviderError {
            #expect(error == .unsupportedStream)
        }
    }

    @Test
    func modelDiscoverySortsDeduplicatesAndKeepsOrder() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(
                headers: ["Content-Type": "application/json"],
                chunks: [
                    Data("{\"data\":[{\"id\":\"zeta\"},{\"id\":\"alpha\"},{\"id\":\"beta\"},{\"id\":\"alpha\"}]}".utf8)
                ]
            )
        }
        let client = OpenAICompatibleClient(session: makeSession())
        let models = try await client.fetchModels(profile: localProfile(), apiKey: " secret ")
        let request = try #require(AssistantStubURLProtocol.lastRequest)

        #expect(models == ["alpha", "beta", "zeta"])
        #expect(request.url?.path == "/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test
    func timeoutIsActionable() async throws {
        AssistantStubURLProtocol.replyProvider = { _ in
            AssistantStubReply(failure: URLError(.timedOut))
        }
        let provider = try makeProvider()

        do {
            _ = try await collect(provider)
            Issue.record("Expected timeout error.")
        } catch let error as AssistantProviderError {
            #expect(error == .timedOut)
        }
    }

    @Test
    func cancelledRequestIsNotReportedAsOffline() {
        #expect(AssistantProviderError.normalize(URLError(.cancelled)) is CancellationError)
    }

    @Test
    func networkErrorMappingIsStable() {
        #expect(AssistantProviderError.normalize(URLError(.timedOut)) as? AssistantProviderError == .timedOut)
        #expect(AssistantProviderError.normalize(CancellationError()) is CancellationError)
        #expect(AssistantProviderError.normalize(URLError(.cannotConnectToHost)) as? AssistantProviderError == .offline)
    }

    private func makeProvider(settings: AssistantSettings = AssistantSettings()) throws -> OpenAICompatibleProvider {
        try OpenAICompatibleProvider(
            profile: localProfile(),
            apiKey: "secret",
            settings: settings,
            session: makeSession()
        )
    }

    private func localProfile() -> AssistantProviderProfile {
        AssistantProviderProfile(
            name: "Local",
            baseURL: "http://127.0.0.1:1234/v1",
            model: "test-model",
            isLocal: true
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssistantStubURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        return URLSession(configuration: configuration)
    }

    private func collect(_ provider: OpenAICompatibleProvider) async throws -> [AssistantTransportEvent] {
        let request = AssistantRequest(
            prompt: "Explain",
            conversation: [AssistantMessage(role: .user, content: "Explain")],
            systemInstructions: "System",
            context: nil
        )
        var events: [AssistantTransportEvent] = []
        for try await event in provider.stream(request) {
            events.append(event)
        }
        return events
    }
}
