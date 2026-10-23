import Foundation

enum AssistantConnectionState: String, Codable, Hashable, Sendable {
    case local
    case remote
    case checking
    case offline
    case needsSetup

    var label: String {
        switch self {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        case .checking:
            return "Checking"
        case .offline:
            return "Offline"
        case .needsSetup:
            return "Needs setup"
        }
    }

    var isUsable: Bool {
        self == .local || self == .remote
    }
}

struct AssistantProvider: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var model: String
    var connection: AssistantConnectionState

    init(
        id: String,
        name: String,
        model: String,
        connection: AssistantConnectionState
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.connection = connection
    }

    static let mock = AssistantProvider(
        id: "mock",
        name: "Mock Provider",
        model: "Local preview",
        connection: .local
    )

    var isUsable: Bool {
        connection.isUsable
    }

    var subtitle: String {
        "\(name) · \(model) · \(connection.label)"
    }
}
