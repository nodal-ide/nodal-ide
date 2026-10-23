import Foundation

enum AssistantMessageRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
}

enum AssistantMessageStatus: String, Codable, Hashable, Sendable {
    case complete
    case streaming
    case stopped
    case failed
}

struct AssistantCitation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var relativePath: String
    var line: Int?
    var endLine: Int?
    var knowledgeSourceID: String?

    init(
        id: String,
        title: String,
        relativePath: String,
        line: Int? = nil,
        endLine: Int? = nil,
        knowledgeSourceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.line = line
        self.endLine = endLine
        self.knowledgeSourceID = knowledgeSourceID
    }
}

struct AssistantMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var role: AssistantMessageRole
    var content: String
    var createdAt: Date
    var status: AssistantMessageStatus
    var citations: [AssistantCitation]
    var contextDescriptors: [AssistantContextDescriptor]
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        role: AssistantMessageRole,
        content: String,
        createdAt: Date = Date(),
        status: AssistantMessageStatus = .complete,
        citations: [AssistantCitation] = [],
        contextDescriptors: [AssistantContextDescriptor] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
        self.citations = citations
        self.contextDescriptors = contextDescriptors
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case status
        case citations
        case contextDescriptors
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AssistantMessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        status = try container.decodeIfPresent(AssistantMessageStatus.self, forKey: .status) ?? .complete
        citations = try container.decodeIfPresent([AssistantCitation].self, forKey: .citations) ?? []
        contextDescriptors =
            try container.decodeIfPresent([AssistantContextDescriptor].self, forKey: .contextDescriptors) ?? []
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    var isUser: Bool {
        role == .user
    }
}
