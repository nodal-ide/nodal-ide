import Foundation

struct UnavailableAssistantTransport: AssistantTransport {
    let error: AssistantProviderError

    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantTransportEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
