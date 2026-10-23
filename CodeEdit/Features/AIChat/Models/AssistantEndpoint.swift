import Foundation

enum AssistantEndpointError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case unsupportedScheme
    case missingHost
    case embeddedCredentials
    case queryOrFragment
    case insecureHTTP
    case fullEndpointPath

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid provider base URL."
        case .unsupportedScheme:
            return "The provider URL must use HTTPS, or HTTP for a local server."
        case .missingHost:
            return "The provider URL is missing a host."
        case .embeddedCredentials:
            return "Remove credentials from the provider URL and enter the API key separately."
        case .queryOrFragment:
            return "The provider base URL cannot contain a query or fragment."
        case .insecureHTTP:
            return "Remote providers require HTTPS. Enable insecure HTTP only for a trusted local server."
        case .fullEndpointPath:
            return "Use the API base URL (ending in /v1), not the chat or models endpoint."
        }
    }
}

struct AssistantEndpoint: Equatable, Sendable {
    let baseURL: URL
    let chatCompletionsURL: URL
    let modelsURL: URL
    let isLoopback: Bool

    // swiftlint:disable:next cyclomatic_complexity
    init(baseURLString: String, allowInsecureHTTP: Bool) throws {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            throw AssistantEndpointError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw AssistantEndpointError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw AssistantEndpointError.embeddedCredentials
        }
        guard components.query == nil, components.fragment == nil else {
            throw AssistantEndpointError.queryOrFragment
        }

        let loopback = Self.isLoopback(host)
        guard scheme == "https" || loopback || allowInsecureHTTP else {
            throw AssistantEndpointError.insecureHTTP
        }

        var path = components.path
        if path == "/" {
            path = ""
        }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        guard !path.hasSuffix("/chat/completions"), !path.hasSuffix("/models") else {
            throw AssistantEndpointError.fullEndpointPath
        }
        if path.isEmpty {
            path = "/v1"
        } else if !path.hasSuffix("/v1") {
            path += "/v1"
        }
        components.path = path

        guard let baseURL = components.url else {
            throw AssistantEndpointError.invalidURL
        }

        self.baseURL = baseURL
        self.chatCompletionsURL = baseURL.appendingPathComponent("chat/completions")
        self.modelsURL = baseURL.appendingPathComponent("models")
        self.isLoopback = loopback
    }

    var displayHost: String {
        guard let host = baseURL.host else { return baseURL.absoluteString }
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        if let port = baseURL.port {
            return "\(formattedHost):\(port)"
        }
        return formattedHost
    }

    private static func isLoopback(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized == "::1" || normalized == "[::1]" {
            return true
        }
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets[0] == "127" else { return false }
        return octets.dropFirst().allSatisfy { octet in
            guard let value = Int(octet) else { return false }
            return (0...255).contains(value)
        }
    }
}

struct AssistantOrigin: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL?) {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "https" ? 443 : 80)
    }

    func matches(_ other: AssistantOrigin?) -> Bool {
        self == other
    }
}
