import Foundation

struct AssistantProviderProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var baseURL: String
    var model: String
    var isLocal: Bool
    var allowInsecureHTTP: Bool
    var compatibilityMode: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        model: String,
        isLocal: Bool,
        allowInsecureHTTP: Bool = false,
        compatibilityMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.isLocal = isLocal
        self.allowInsecureHTTP = allowInsecureHTTP
        self.compatibilityMode = compatibilityMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Provider"
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        self.isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        self.allowInsecureHTTP =
            try container.decodeIfPresent(Bool.self, forKey: .allowInsecureHTTP) ?? false
        self.compatibilityMode =
            try container.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false
    }

    var keychainAccount: String {
        id.uuidString.lowercased()
    }
}

enum AssistantProviderPreset: String, CaseIterable, Identifiable, Sendable {
    case lmStudio
    case ollama
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lmStudio:
            return "LM Studio"
        case .ollama:
            return "Ollama"
        case .custom:
            return "Custom Endpoint"
        }
    }

    var subtitle: String {
        switch self {
        case .lmStudio:
            return "http://127.0.0.1:1234/v1"
        case .ollama:
            return "http://127.0.0.1:11434/v1"
        case .custom:
            return "Any OpenAI-compatible HTTPS server"
        }
    }

    func makeProfile(id: UUID = UUID()) -> AssistantProviderProfile {
        switch self {
        case .lmStudio:
            return AssistantProviderProfile(
                id: id,
                name: "LM Studio",
                baseURL: "http://127.0.0.1:1234/v1",
                model: "",
                isLocal: true
            )
        case .ollama:
            return AssistantProviderProfile(
                id: id,
                name: "Ollama",
                baseURL: "http://127.0.0.1:11434/v1",
                model: "",
                isLocal: true
            )
        case .custom:
            return AssistantProviderProfile(
                id: id,
                name: "Custom Provider",
                baseURL: "",
                model: "",
                isLocal: false
            )
        }
    }
}

struct AssistantSettings: Codable, Hashable, Sendable {
    var profiles: [AssistantProviderProfile] = []
    var defaultProfileID: UUID?
    var streamResponses = true
    var temperature = 0.2
    var maxOutputTokens = 2_048
    var contextWindowTokens = 8_192
    var retrieveWorkspaceExcerpts = true
    var includeDiagnosticsByDefault = true
    var includeTasksByDefault = true
    var saveHistory = true
    var remoteWorkspaceContextConsent: [UUID: Bool] = [:]

    static let searchKeys = [
        "AI Assistant",
        "Provider",
        "Endpoint",
        "API Key",
        "Model",
        "Temperature",
        "Streaming",
        "Context Window",
        "Workspace Context",
        "History"
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProfiles =
            (try? container.decodeIfPresent(
                [LossyAssistantProviderProfile].self,
                forKey: .profiles
            )) ?? []
        self.profiles = decodedProfiles.compactMap(\.profile)
        self.defaultProfileID =
            try? container.decodeIfPresent(UUID.self, forKey: .defaultProfileID)
        self.streamResponses =
            (try? container.decodeIfPresent(Bool.self, forKey: .streamResponses)) ?? true
        self.temperature =
            (try? container.decodeIfPresent(Double.self, forKey: .temperature)) ?? 0.2
        self.maxOutputTokens =
            (try? container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)) ?? 2_048
        self.contextWindowTokens =
            (try? container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)) ?? 8_192
        self.retrieveWorkspaceExcerpts =
            (try? container.decodeIfPresent(Bool.self, forKey: .retrieveWorkspaceExcerpts)) ?? true
        self.includeDiagnosticsByDefault =
            (try? container.decodeIfPresent(Bool.self, forKey: .includeDiagnosticsByDefault)) ?? true
        self.includeTasksByDefault =
            (try? container.decodeIfPresent(Bool.self, forKey: .includeTasksByDefault)) ?? true
        self.saveHistory =
            (try? container.decodeIfPresent(Bool.self, forKey: .saveHistory)) ?? true
        self.remoteWorkspaceContextConsent =
            (try? container.decodeIfPresent(
                [UUID: Bool].self,
                forKey: .remoteWorkspaceContextConsent
            )) ?? [:]
    }

    func allowsRemoteWorkspaceContext(for profileID: UUID) -> Bool {
        remoteWorkspaceContextConsent[profileID] == true
    }

    var defaultProfile: AssistantProviderProfile? {
        if let defaultProfileID,
           let profile = profiles.first(where: { $0.id == defaultProfileID }) {
            return profile
        }
        return profiles.first
    }
}

private struct LossyAssistantProviderProfile: Decodable {
    let profile: AssistantProviderProfile?

    init(from decoder: Decoder) throws {
        profile = try? AssistantProviderProfile(from: decoder)
    }
}
