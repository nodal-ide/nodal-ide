import Foundation

struct AssistantContextDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: AssistantContextItem.Kind
    let title: String
    let relativePath: String?
    let startLine: Int?
    let endLine: Int?
    let languageID: String?
    let knowledgeSourceID: String?
    let isTruncated: Bool
    let isSensitive: Bool

    init(item: AssistantContextItem) {
        id = item.id
        kind = item.kind
        title = item.title
        relativePath = item.relativePath
        startLine = item.lineRange?.lowerBound
        endLine = item.lineRange?.upperBound
        languageID = item.languageID
        knowledgeSourceID = item.knowledgeSourceID
        isTruncated = item.isTruncated
        isSensitive = item.isSensitive
    }
}

struct AssistantConversation: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [AssistantMessage]
    var providerID: String?
    var providerName: String?
    var model: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AssistantMessage],
        providerID: String? = nil,
        providerName: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.providerID = providerID
        self.providerName = providerName
        self.model = model
    }

    static func defaultTitle(from messages: [AssistantMessage]) -> String {
        let prompt = messages.first {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.content ?? ""
        let collapsed = prompt
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "New Conversation" }
        guard collapsed.count > 60 else { return collapsed }
        return String(collapsed.prefix(57)) + "…"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case messages
        case providerID
        case providerName
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New Conversation"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        let decodedMessages =
            try container.decodeIfPresent([LossyAssistantMessage].self, forKey: .messages) ?? []
        messages = decodedMessages.compactMap(\.message)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        model = try container.decodeIfPresent(String.self, forKey: .model)
    }
}

struct AssistantConversationArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var lastOpenedConversationID: UUID?
    var conversations: [AssistantConversation]

    static let empty = AssistantConversationArchive(
        schemaVersion: currentSchemaVersion,
        lastOpenedConversationID: nil,
        conversations: []
    )

    init(
        schemaVersion: Int = AssistantConversationArchive.currentSchemaVersion,
        lastOpenedConversationID: UUID?,
        conversations: [AssistantConversation]
    ) {
        self.schemaVersion = schemaVersion
        self.lastOpenedConversationID = lastOpenedConversationID
        self.conversations = conversations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case lastOpenedConversationID
        case conversations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion =
            try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? AssistantConversationArchive.currentSchemaVersion
        lastOpenedConversationID =
            try container.decodeIfPresent(UUID.self, forKey: .lastOpenedConversationID)
        let decoded =
            try container.decodeIfPresent([LossyAssistantConversation].self, forKey: .conversations) ?? []
        conversations = decoded.compactMap(\.conversation)
    }
}

private struct LossyAssistantMessage: Decodable {
    let message: AssistantMessage?

    init(from decoder: Decoder) throws {
        message = try? AssistantMessage(from: decoder)
    }
}

private struct LossyAssistantConversation: Decodable {
    let conversation: AssistantConversation?

    init(from decoder: Decoder) throws {
        conversation = try? AssistantConversation(from: decoder)
    }
}
