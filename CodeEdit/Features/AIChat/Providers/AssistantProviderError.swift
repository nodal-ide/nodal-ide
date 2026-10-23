import Foundation

enum AssistantProviderError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case remoteContextConsentRequired(host: String)
    case unauthorized
    case modelNotFound
    case rateLimited(retryAfter: Int?)
    case server(statusCode: Int, message: String?)
    case offline
    case timedOut
    case malformedStream
    case unsupportedStream
    case reasoningOnlyResponse
    case contextOverflow
    case redirectRejected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case let .remoteContextConsentRequired(host):
            return "Workspace context is disabled for this remote provider. "
                + "Enable it for \(host) in Settings > AI Assistant, or send without context."
        case .unauthorized:
            return "The provider rejected the API key. "
                + "Re-enter the key or check the provider settings."
        case .modelNotFound:
            return "The provider could not find this model. Refresh the model list or edit the model ID."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                return "The provider is rate limiting requests. Retry in \(retryAfter) seconds."
            }
            return "The provider is rate limiting requests. Wait a moment, then retry."
        case let .server(statusCode, message):
            if let message, !message.isEmpty {
                return "The provider returned HTTP \(statusCode): \(message)"
            }
            return "The provider returned HTTP \(statusCode). Retry or check the endpoint."
        case .offline:
            return "The provider could not be reached. Check that it is running and that the address is correct."
        case .timedOut:
            return "The provider did not respond in time. Check the endpoint or retry."
        case .malformedStream:
            return "The provider sent a malformed streaming response. Retry the request."
        case .unsupportedStream:
            return "The provider did not return a streaming response. "
                + "Disable streaming for this profile or check the server."
        case .reasoningOnlyResponse:
            return "The model used its output budget on reasoning without producing an answer. "
                + "Increase Max output tokens or choose a non-reasoning model."
        case .contextOverflow:
            return "The selected context is too large for this model. Remove context or reduce the output limit."
        case .redirectRejected:
            return "The provider redirected to a different origin. Check the endpoint URL."
        case .invalidResponse:
            return "The provider returned an unexpected response. Check the endpoint and model."
        }
    }

    static func http(
        statusCode: Int,
        body: Data,
        retryAfter: String?
    ) -> AssistantProviderError {
        let message = errorMessage(from: body)
        let lowercased = message?.lowercased() ?? ""
        if statusCode == 401 || statusCode == 403 {
            return .unauthorized
        }
        if statusCode == 404 {
            return .modelNotFound
        }
        if statusCode == 429 {
            return .rateLimited(retryAfter: retryAfter.flatMap(Int.init))
        }
        let isContextError = lowercased.contains("context length")
            || lowercased.contains("context window")
            || lowercased.contains("too many tokens")
            || lowercased.contains("maximum context")
        if statusCode == 400, isContextError {
            return .contextOverflow
        }
        return .server(statusCode: statusCode, message: message)
    }

    static func normalize(_ error: Error) -> Error {
        if error is CancellationError {
            return CancellationError()
        }
        if let providerError = error as? AssistantProviderError {
            return providerError
        }
        if error is DecodingError {
            return AssistantProviderError.invalidResponse
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return CancellationError()
            case .timedOut:
                return AssistantProviderError.timedOut
            case .notConnectedToInternet,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .resourceUnavailable:
                return AssistantProviderError.offline
            case .appTransportSecurityRequiresSecureConnection:
                return AssistantProviderError.invalidConfiguration(
                    "This endpoint was blocked by App Transport Security. Use HTTPS or a local server."
                )
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid:
                return AssistantProviderError.invalidConfiguration(
                    "The provider's TLS certificate could not be verified. Check the endpoint."
                )
            default:
                return AssistantProviderError.offline
            }
        }
        return error
    }

    static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty, data.count <= 64 * 1_024 else { return nil }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return String(message.prefix(500))
        }
        return nil
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorPayload?
    }

    private struct ErrorPayload: Decodable {
        let message: String?
    }
}
