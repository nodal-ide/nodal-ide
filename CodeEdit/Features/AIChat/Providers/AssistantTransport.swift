import Foundation

struct AssistantRequest: Equatable, Sendable {
    var prompt: String
    var conversation: [AssistantMessage]
}

enum AssistantTransportEvent: Equatable, Sendable {
    case delta(String)
    case completed
}

enum AssistantTransportError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}

protocol AssistantTransport: Sendable {
    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantTransportEvent, Error>
}
