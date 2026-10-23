@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct AssistantSessionTests {
    @Test
    func sendAppendsMessagesAndStreamsResponse() async {
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0, chunkSize: 10_000),
            provider: .mock
        )
        session.draft = "  Explain this  "

        session.send()

        #expect(session.draft.isEmpty)
        #expect(session.isStreaming)
        #expect(session.messages.count == 2)
        #expect(session.messages.first?.role == .user)
        #expect(session.messages.first?.content == "Explain this")
        #expect(session.messages.last?.role == .assistant)
        #expect(session.messages.last?.status == .streaming)

        await waitForIdle(session)

        #expect(session.messages.last?.status == .complete)
        #expect(session.messages.last?.content.isEmpty == false)
        #expect(session.contentRevision > 0)
    }

    @Test
    func sendRejectsBlankDraftsAndUnusableProviders() {
        let session = AssistantSession(transport: MockAssistantTransport(chunkDelayNanoseconds: 0))
        session.draft = "   \n"
        session.send()
        #expect(session.messages.isEmpty)

        let noProviderSession = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: nil
        )
        noProviderSession.draft = "Hello"
        #expect(!noProviderSession.canSend)
        #expect(noProviderSession.destinationLabel == "No provider configured")

        let offlineSession = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: AssistantProvider(
                id: "offline",
                name: "Offline",
                model: "None",
                connection: .offline
            )
        )
        offlineSession.draft = "Hello"
        #expect(!offlineSession.canSend)
        offlineSession.send()
        #expect(offlineSession.messages.isEmpty)
        #expect(offlineSession.draft == "Hello")
    }

    @Test
    func draftIsTruncatedToMaximumLength() {
        let session = AssistantSession(transport: MockAssistantTransport(chunkDelayNanoseconds: 0))
        session.draft = String(repeating: "a", count: AssistantSession.maximumDraftLength + 1)

        #expect(session.draft.count == AssistantSession.maximumDraftLength)
    }

    @Test
    func stopPreservesPartialResponseAndMarksMessageStopped() async {
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 20_000_000, chunkSize: 4),
            provider: .mock
        )
        session.draft = "Keep going"
        session.send()

        await waitForExpectation {
            session.messages.last?.content.isEmpty == false
        } onTimeout: {
            Issue.record("The mock provider never emitted a chunk.")
        }

        let partialContent = session.messages.last?.content
        session.stop()

        #expect(!session.isStreaming)
        #expect(session.messages.last?.status == .stopped)
        #expect(session.messages.last?.content == partialContent)

        try? await Task.sleep(for: .milliseconds(60))
        #expect(session.messages.last?.content == partialContent)
    }

    @Test
    func transportFailureMarksMessageFailed() async {
        let session = AssistantSession(
            transport: MockAssistantTransport(scenario: .error, chunkDelayNanoseconds: 0),
            provider: .mock
        )
        session.draft = "Hello"
        session.send()

        await waitForExpectation {
            session.messages.last?.status == .failed
        } onTimeout: {
            Issue.record("The failing mock provider never reported an error.")
        }

        #expect(!session.isStreaming)
        #expect(session.messages.last?.content.isEmpty == false)
        #expect(
            session.messages.last?.errorMessage
                == "The mock provider is unavailable. Check the provider configuration."
        )
    }

    @Test
    func emptyResponseMarksMessageFailed() async {
        let session = AssistantSession(
            transport: MockAssistantTransport(scenario: .empty, chunkDelayNanoseconds: 0),
            provider: .mock
        )
        session.draft = "Hello"
        session.send()

        await waitForExpectation {
            session.messages.last?.status == .failed
        } onTimeout: {
            Issue.record("The empty mock provider never finished.")
        }

        #expect(session.messages.last?.content.isEmpty == true)
        #expect(session.messages.last?.errorMessage == "The assistant returned an empty response.")
    }

    @Test
    func retryReplacesFailedResponseWithSamePrompt() async throws {
        let transport = RetryTransport()
        let session = AssistantSession(transport: transport, provider: .mock)
        session.draft = "Original prompt"
        session.send()

        await waitForExpectation {
            session.messages.last?.status == .failed
        } onTimeout: {
            Issue.record("The first attempt never failed.")
        }

        let failedMessageID = try #require(session.messages.last?.id)
        session.retry(failedMessageID)

        #expect(session.isStreaming)
        #expect(session.messages.count == 2)
        await waitForIdle(session)

        #expect(session.messages.last?.status == .complete)
        #expect(session.messages.last?.content == "recovered")
        #expect(session.messages.last?.id != failedMessageID)

        let requests = transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].prompt == "Original prompt")
        #expect(requests[1].conversation.map(\.role) == [.user])
        #expect(requests[1].conversation.first?.content == "Original prompt")
    }

    @Test
    func startingNewConversationCancelsStreamingAndClearsState() async throws {
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 20_000_000, chunkSize: 2),
            provider: .mock
        )
        session.draft = "Long answer"
        session.send()

        await waitForExpectation {
            session.messages.last?.content.isEmpty == false
        } onTimeout: {
            Issue.record("The mock provider never emitted a chunk.")
        }

        session.startNewConversation()
        let focusRequest = session.focusRequest

        #expect(session.messages.isEmpty)
        #expect(session.draft.isEmpty)
        #expect(!session.isStreaming)

        try await Task.sleep(for: .milliseconds(60))
        #expect(session.messages.isEmpty)
        #expect(session.focusRequest == focusRequest)
    }

    @Test
    func transcriptFormatsUserAndAssistantMessages() {
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            messages: [
                AssistantMessage(role: .user, content: "Hi"),
                AssistantMessage(role: .assistant, content: "Hello")
            ]
        )

        #expect(session.transcript == "You\nHi\n\nAssistant\nHello")
        #expect(session.copyTranscript() == session.transcript)
    }

    private func waitForIdle(
        _ session: AssistantSession,
        timeout: Duration = .seconds(2)
    ) async {
        await waitForExpectation(timeout: timeout) {
            !session.isStreaming
        } onTimeout: {
            Issue.record("Assistant session did not finish streaming in time.")
        }
    }
}

private final class RetryTransport: AssistantTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [AssistantRequest] = []
    private var attempts = 0

    var requests: [AssistantRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantTransportEvent, Error> {
        lock.lock()
        storedRequests.append(request)
        let attempt = attempts
        attempts += 1
        lock.unlock()

        return AsyncThrowingStream { continuation in
            let task = Task {
                if attempt == 0 {
                    continuation.yield(.delta("partial"))
                    continuation.finish(throwing: AssistantTransportError.failed("Mock failure"))
                } else {
                    continuation.yield(.delta("recovered"))
                    continuation.yield(.completed)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
