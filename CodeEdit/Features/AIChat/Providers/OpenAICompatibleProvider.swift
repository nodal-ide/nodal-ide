import Foundation

struct OpenAICompatibleProvider: AssistantTransport {
    let profile: AssistantProviderProfile
    let endpoint: AssistantEndpoint
    let apiKey: String?
    let settings: AssistantSettings
    let session: URLSession
    let idleTimeout: TimeInterval
    let totalTimeout: TimeInterval

    init(
        profile: AssistantProviderProfile,
        apiKey: String?,
        settings: AssistantSettings,
        session: URLSession = .shared,
        idleTimeout: TimeInterval = 60,
        totalTimeout: TimeInterval = 600
    ) throws {
        self.profile = profile
        self.endpoint = try AssistantEndpoint(
            baseURLString: profile.baseURL,
            allowInsecureHTTP: profile.allowInsecureHTTP
        )
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.settings = settings
        self.session = session
        self.idleTimeout = idleTimeout
        self.totalTimeout = totalTimeout
    }

    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantTransportEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try validateRemoteContextConsent(for: request)
                    if settings.streamResponses {
                        try await streamResponse(request, continuation: continuation)
                    } else {
                        try await loadResponse(request, continuation: continuation)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: AssistantProviderError.normalize(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func validateRemoteContextConsent(for request: AssistantRequest) throws {
        guard request.context != nil,
              !endpoint.isLoopback,
              !settings.allowsRemoteWorkspaceContext(for: profile.id)
        else { return }
        throw AssistantProviderError.remoteContextConsentRequired(host: endpoint.displayHost)
    }

    private func streamResponse(
        _ request: AssistantRequest,
        continuation: AsyncThrowingStream<AssistantTransportEvent, Error>.Continuation
    ) async throws {
        let urlRequest = try makeRequest(for: request, stream: true)
        let origin = AssistantOrigin(url: endpoint.baseURL)
        let redirectDelegate = AssistantRedirectDelegate(origin: origin)
        let (bytes, response) = try await session.bytes(for: urlRequest, delegate: redirectDelegate)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantProviderError.invalidResponse
        }
        guard AssistantOrigin(url: httpResponse.url)?.matches(origin) == true else {
            throw AssistantProviderError.redirectRejected
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = try await readBoundedBody(bytes, limit: 64 * 1_024)
            throw AssistantProviderError.http(
                statusCode: httpResponse.statusCode,
                body: body,
                retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After")
            )
        }
        if let mimeType = httpResponse.mimeType, mimeType != "text/event-stream" {
            throw AssistantProviderError.unsupportedStream
        }

        let deadline = Date().addingTimeInterval(totalTimeout)
        var decoder = SSEStreamDecoder()
        let state = StreamState()

        for try await byte in bytes {
            try Task.checkCancellation()
            if Date() > deadline {
                throw AssistantProviderError.timedOut
            }
            for event in try decoder.append(byte)
            where try handle(event, continuation: continuation, state: state) {
                state.sawDone = true
                break
            }
            if state.sawDone {
                break
            }
        }

        if !state.sawDone {
            for event in try decoder.finish()
            where try handle(event, continuation: continuation, state: state) {
                break
            }
        }
        try validateStreamCompletion(state)
        continuation.yield(.completed)
    }

    private func loadResponse(
        _ request: AssistantRequest,
        continuation: AsyncThrowingStream<AssistantTransportEvent, Error>.Continuation
    ) async throws {
        let urlRequest = try makeRequest(for: request, stream: false)
        let origin = AssistantOrigin(url: endpoint.baseURL)
        let redirectDelegate = AssistantRedirectDelegate(origin: origin)
        let (data, response) = try await session.data(for: urlRequest, delegate: redirectDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantProviderError.invalidResponse
        }
        guard AssistantOrigin(url: httpResponse.url)?.matches(origin) == true else {
            throw AssistantProviderError.redirectRejected
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AssistantProviderError.http(
                statusCode: httpResponse.statusCode,
                body: data,
                retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After")
            )
        }
        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            throw AssistantProviderError.invalidResponse
        }
        let message = decoded.choices?.first?.message
        if let content = message?.content, !content.isEmpty {
            continuation.yield(.delta(content))
        } else if let reasoning = message?.reasoning ?? message?.reasoningContent, !reasoning.isEmpty {
            throw AssistantProviderError.reasoningOnlyResponse
        }
        continuation.yield(.completed)
    }

    private func handle(
        _ event: SSEStreamEvent,
        continuation: AsyncThrowingStream<AssistantTransportEvent, Error>.Continuation,
        state: StreamState
    ) throws -> Bool {
        guard case .event(_, let data) = event else { return false }
        if data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return true
        }
        guard let data = data.data(using: .utf8) else {
            throw AssistantProviderError.malformedStream
        }
        guard let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else {
            throw AssistantProviderError.malformedStream
        }
        if let message = chunk.error?.message, !message.isEmpty {
            throw AssistantProviderError.server(statusCode: 200, message: String(message.prefix(500)))
        }
        let delta = chunk.choices?.first?.delta
        if let content = delta?.content, !content.isEmpty {
            state.sawContent = true
            continuation.yield(.delta(content))
        }
        if let reasoning = delta?.reasoning ?? delta?.reasoningContent, !reasoning.isEmpty {
            state.sawReasoning = true
        }
        return false
    }

    private func validateStreamCompletion(_ state: StreamState) throws {
        guard state.sawReasoning, !state.sawContent else { return }
        throw AssistantProviderError.reasoningOnlyResponse
    }

    private final class StreamState {
        var sawDone = false
        var sawReasoning = false
        var sawContent = false
    }

    private func makeRequest(for request: AssistantRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(url: endpoint.chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = idleTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
            stream ? "text/event-stream" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(
            ChatRequestPayload(
                request: request,
                profile: profile,
                settings: settings,
                stream: stream
            )
        )
        return urlRequest
    }

    private func readBoundedBody(
        _ bytes: URLSession.AsyncBytes,
        limit: Int
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 16 * 1_024))
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                break
            }
        }
        return data
    }

}

struct ChatRequestPayload: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?

    init(
        request: AssistantRequest,
        profile: AssistantProviderProfile,
        settings: AssistantSettings,
        stream: Bool
    ) {
        self.model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.stream = stream
        self.temperature = profile.compatibilityMode ? nil : settings.temperature
        self.maxTokens = profile.compatibilityMode ? nil : max(1, settings.maxOutputTokens)

        var system = request.systemInstructions?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if system.isEmpty {
            system = AssistantPromptComposer.systemInstructions
        }
        if let context = request.context {
            system += "\n\n" + AssistantPromptComposer.contextText(for: context)
        }

        var messages = [Message(role: "system", content: system)]
        messages.append(contentsOf: request.conversation.compactMap { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return Message(role: message.role.rawValue, content: message.content)
        })

        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty,
           messages.last?.role != AssistantMessageRole.user.rawValue
            || messages.last?.content != request.prompt {
            messages.append(Message(role: "user", content: request.prompt))
        }
        self.messages = messages
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

final class AssistantRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: AssistantOrigin?

    init(origin: AssistantOrigin?) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard AssistantOrigin(url: request.url)?.matches(origin) == true else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
