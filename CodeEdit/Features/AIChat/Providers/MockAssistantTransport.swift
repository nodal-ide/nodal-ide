import Foundation

enum MockAssistantScenario: String, CaseIterable, Identifiable, Sendable {
    case standard
    case long
    case error
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard response"
        case .long:
            return "Long response"
        case .error:
            return "Failed response"
        case .empty:
            return "Empty response"
        }
    }
}

struct MockAssistantTransport: AssistantTransport {
    var scenario: MockAssistantScenario
    var chunkDelayNanoseconds: UInt64
    var chunkSize: Int

    init(
        scenario: MockAssistantScenario = .standard,
        chunkDelayNanoseconds: UInt64 = 18_000_000,
        chunkSize: Int = 16
    ) {
        self.scenario = scenario
        self.chunkDelayNanoseconds = chunkDelayNanoseconds
        self.chunkSize = max(1, chunkSize)
    }

    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantTransportEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if scenario == .error {
                        try await emitFailure(continuation)
                    } else if scenario == .empty {
                        try await Task.sleep(nanoseconds: chunkDelayNanoseconds)
                        continuation.yield(.completed)
                        continuation.finish()
                    } else {
                        try await emitResponse(continuation, request: request)
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func emitResponse(
        _ continuation: AsyncThrowingStream<AssistantTransportEvent, Error>.Continuation,
        request: AssistantRequest
    ) async throws {
        let response = scenario == .long ? Self.longResponse(for: request.prompt) : Self.response(for: request.prompt)
        let characters = Array(response)
        var index = 0
        while index < characters.count {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: chunkDelayNanoseconds)
            let end = min(index + chunkSize, characters.count)
            continuation.yield(.delta(String(characters[index..<end])))
            index = end
        }
        continuation.yield(.completed)
        continuation.finish()
    }

    private func emitFailure(
        _ continuation: AsyncThrowingStream<AssistantTransportEvent, Error>.Continuation
    ) async throws {
        for chunk in ["The mock provider started a response but could not finish it."] {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: chunkDelayNanoseconds)
            continuation.yield(.delta(chunk))
        }
        throw AssistantTransportError.failed("The mock provider is unavailable. Check the provider configuration.")
    }

    private static func response(for prompt: String) -> String {
        let subject = prompt.isEmpty ? "this code" : "your question"
        return """
        Here is a focused way to approach \(subject).

        ### Suggested approach

        1. Start with the smallest behavior that proves the idea.
        2. Keep the data flow explicit and testable.
        3. Verify the edge cases before widening the change.

        ```swift
        struct Summary: Equatable {
            let title: String
            let itemCount: Int
        }
        ```

        The important part is the boundary: keep the view focused on presentation and move decisions \
        into a small model. That makes the behavior easy to test and keeps the UI predictable.

        **Watch for:** empty input, repeated submissions, and cancellation while work is in flight.
        """
    }

    private static func longResponse(for prompt: String) -> String {
        let subject = prompt.isEmpty ? "this code" : "your question"
        return """
        Here is a longer review of \(subject), organized around behavior, structure, and risk.

        ## What I would verify first

        The current flow is easy to follow, but it mixes presentation state with the operation that produces \
        the result. I would separate those responsibilities so each one has a single reason to change.

        ### Behavior

        - Confirm the empty state never submits an empty request.
        - Keep the draft intact when a request fails.
        - Preserve partial output when the user stops generation.
        - Make retry use the same conversation context as the original attempt.

        ### Structure

        A small session object can own the transcript and the active request. The view should only render state \
        and forward intents. That keeps the feature testable without a window.

        ```swift
        @MainActor
        final class ChatSession: ObservableObject {
            @Published private(set) var messages: [Message] = []
            @Published private(set) var isStreaming = false

            func send(_ text: String) {
                guard !text.isEmpty else { return }
                messages.append(Message(role: .user, text: text))
            }
        }
        ```

        ### Risks

        | Risk | Mitigation |
        | --- | --- |
        | Lost state on tab switch | Own the session above the tab view |
        | Burst updates while streaming | Coalesce text updates before rendering |
        | Unexpected network use | Require an explicit send and show the destination |

        ### Next step

        Implement the narrowest end-to-end path first: type, send, stream, stop, and retry with a mock transport. \
        Then add real configuration once the interaction is stable.

        > Keep the first version inspectable. A predictable assistant is more useful than a clever one that \
        hides what it is doing.
        """
    }
}
