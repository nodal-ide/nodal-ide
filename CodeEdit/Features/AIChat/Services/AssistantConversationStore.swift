import CryptoKit
import Foundation

struct AssistantConversationRetention: Equatable, Sendable {
    var maximumConversations = 40
    var maximumAge: TimeInterval = 90 * 24 * 60 * 60
    var maximumBytes = 4_000_000
}

enum AssistantConversationStoreError: LocalizedError, Equatable {
    case corruptArchive
    case unsupportedSchema(Int)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .corruptArchive:
            return "The saved conversation history is damaged and was moved aside."
        case .unsupportedSchema(let version):
            return "Conversation history version \(version) is newer than this app can read."
        case .encodingFailed:
            return "The conversation history could not be encoded."
        }
    }
}

struct AssistantConversationStore {
    let workspaceID: String
    let directoryURL: URL
    let archiveURL: URL

    private let fileManager: FileManager
    private let retention: AssistantConversationRetention
    private let writeData: (Data, URL) throws -> Void

    init(
        workspaceURL: URL,
        storageRoot: URL? = nil,
        fileManager: FileManager = .default,
        retention: AssistantConversationRetention = AssistantConversationRetention(),
        writeData: ((Data, URL) throws -> Void)? = nil
    ) {
        let canonicalURL = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
        workspaceID = Self.workspaceHash(for: canonicalURL)
        let base = storageRoot
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                .map { $0.appending(path: "CodeEdit/AssistantConversations", directoryHint: .isDirectory) }
            ?? fileManager.temporaryDirectory
                .appending(path: "CodeEdit/AssistantConversations", directoryHint: .isDirectory)
        directoryURL = base.appending(path: workspaceID, directoryHint: .isDirectory)
        archiveURL = directoryURL.appending(path: "conversations.json")
        self.fileManager = fileManager
        self.retention = retention
        self.writeData = writeData ?? { data, url in
            try data.write(to: url, options: .atomic)
        }
    }

    static func workspaceHash(for workspaceURL: URL) -> String {
        let path = workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        return SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func load() throws -> AssistantConversationArchive {
        guard fileManager.fileExists(atPath: archiveURL.path(percentEncoded: false)) else {
            return .empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: archiveURL)
        } catch {
            quarantineArchive()
            throw AssistantConversationStoreError.corruptArchive
        }

        let decoded: AssistantConversationArchive
        do {
            decoded = try JSONDecoder().decode(AssistantConversationArchive.self, from: data)
        } catch {
            quarantineArchive()
            throw AssistantConversationStoreError.corruptArchive
        }

        guard decoded.schemaVersion == AssistantConversationArchive.currentSchemaVersion else {
            quarantineArchive()
            throw AssistantConversationStoreError.unsupportedSchema(decoded.schemaVersion)
        }

        let normalized = normalized(decoded, normalizeStreaming: true)
        return pruned(normalized)
    }

    @discardableResult
    func save(_ archive: AssistantConversationArchive) throws -> AssistantConversationArchive {
        let normalizedArchive = pruned(normalized(archive, normalizeStreaming: false))
        guard let data = try? JSONEncoder().encode(normalizedArchive) else {
            throw AssistantConversationStoreError.encodingFailed
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path(percentEncoded: false)
        )
        try writeData(data, archiveURL)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: archiveURL.path(percentEncoded: false)
        )

        return normalizedArchive
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private func normalized(
        _ archive: AssistantConversationArchive,
        normalizeStreaming: Bool
    ) -> AssistantConversationArchive {
        var conversations: [AssistantConversation] = []
        var seen = Set<UUID>()

        for var conversation in archive.conversations.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard seen.insert(conversation.id).inserted else { continue }
            if conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversation.title = AssistantConversation.defaultTitle(from: conversation.messages)
            }
            if normalizeStreaming {
                for index in conversation.messages.indices
                where conversation.messages[index].status == .streaming {
                    conversation.messages[index].status = .stopped
                }
            }
            conversations.append(conversation)
        }

        var selectedID = archive.lastOpenedConversationID
        if let id = selectedID,
           !conversations.contains(where: { $0.id == id }) {
            selectedID = nil
        }

        return AssistantConversationArchive(
            schemaVersion: AssistantConversationArchive.currentSchemaVersion,
            lastOpenedConversationID: selectedID,
            conversations: conversations
        )
    }

    private func pruned(_ archive: AssistantConversationArchive) -> AssistantConversationArchive {
        let now = Date()
        var conversations = archive.conversations.filter {
            now.timeIntervalSince($0.updatedAt) <= retention.maximumAge
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }

        if conversations.count > retention.maximumConversations {
            conversations.removeLast(conversations.count - retention.maximumConversations)
        }

        var selectedID = archive.lastOpenedConversationID
        if let id = selectedID,
           !conversations.contains(where: { $0.id == id }) {
            selectedID = nil
        }

        while conversations.count > 1 {
            let candidate = AssistantConversationArchive(
                schemaVersion: AssistantConversationArchive.currentSchemaVersion,
                lastOpenedConversationID: selectedID,
                conversations: conversations
            )
            guard let data = try? JSONEncoder().encode(candidate),
                  data.count > retention.maximumBytes
            else { break }
            conversations.removeLast()
            if let id = selectedID,
               !conversations.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }

        return AssistantConversationArchive(
            schemaVersion: AssistantConversationArchive.currentSchemaVersion,
            lastOpenedConversationID: selectedID,
            conversations: conversations
        )
    }

    private func quarantineArchive() {
        guard fileManager.fileExists(atPath: archiveURL.path(percentEncoded: false)) else { return }
        let suffix = UUID().uuidString.prefix(8)
        let destination = directoryURL.appending(
            path: "conversations-corrupt-\(Int(Date().timeIntervalSince1970))-\(suffix).json"
        )
        try? fileManager.moveItem(at: archiveURL, to: destination)
    }
}
