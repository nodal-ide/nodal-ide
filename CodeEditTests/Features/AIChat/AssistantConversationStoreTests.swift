@testable import CodeEdit
import Foundation
import Testing

@Suite
struct AssistantConversationStoreTests {
    @Test
    func workspaceHashIsStableAndDoesNotExposePath() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }

        let hash = AssistantConversationStore.workspaceHash(for: fixture.workspaceURL)
        #expect(hash == fixture.store.workspaceID)
        #expect(hash.count == 64)
        #expect(!fixture.store.directoryURL.lastPathComponent.contains("Workspace"))
        #expect(!hash.contains(fixture.workspaceURL.lastPathComponent))
    }

    @Test
    func differentWorkspacesUseDifferentArchives() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let otherWorkspace = fixture.workspaceURL
            .deletingLastPathComponent()
            .appending(path: "OtherWorkspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: otherWorkspace, withIntermediateDirectories: true)

        let otherStore = AssistantConversationStore(
            workspaceURL: otherWorkspace,
            storageRoot: fixture.storageRoot
        )

        #expect(otherStore.workspaceID != fixture.store.workspaceID)
        #expect(otherStore.directoryURL != fixture.store.directoryURL)
    }

    @Test
    func saveAndLoadRoundTripPreservesMessagesDescriptorsAndCitations() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }

        let archive = makeRoundTripArchive()

        let saved = try fixture.store.save(archive)
        let loaded = try fixture.store.load()

        let assistantMessage = loaded.conversations.first?.messages.last
        #expect(loaded == saved)
        #expect(assistantMessage?.contextDescriptors.first?.relativePath == "Sources/Loader.swift")
        #expect(assistantMessage?.citations.first?.line == 4)

        let raw = try String(contentsOf: fixture.store.archiveURL, encoding: .utf8)
        #expect(!raw.contains("secret source body"))
        #expect(!raw.contains(fixture.workspaceURL.path(percentEncoded: false)))
    }

    @Test
    func missingArchiveLoadsAsEmptyAndClearRemovesHistory() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }

        #expect(try fixture.store.load() == .empty)

        let conversation = AssistantConversation(
            title: "Temporary",
            messages: [AssistantMessage(role: .user, content: "Hello")]
        )
        try fixture.store.save(
            AssistantConversationArchive(
                lastOpenedConversationID: conversation.id,
                conversations: [conversation]
            )
        )
        try fixture.store.clear()

        #expect(try fixture.store.load() == .empty)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.archiveURL.path(percentEncoded: false)))
    }

    @Test
    func corruptArchiveIsQuarantinedAndRejected() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        try fixture.writeArchive("{not json")

        #expect(throws: AssistantConversationStoreError.corruptArchive) {
            _ = try fixture.store.load()
        }

        let names = try FileManager.default.contentsOfDirectory(
            atPath: fixture.store.directoryURL.path(percentEncoded: false)
        )
        #expect(names.contains { $0.hasPrefix("conversations-corrupt-") })
        #expect(!names.contains("conversations.json"))
    }

    @Test
    func legacyArchiveDefaultsMissingFieldsAndStopsInterruptedMessages() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }

        let conversationID = UUID()
        let messageID = UUID()
        let json: [String: Any] = [
            "conversations": [
                [
                    "id": conversationID.uuidString,
                    "title": "Legacy",
                    "unknownField": true,
                    "messages": [
                        [
                            "id": messageID.uuidString,
                            "role": "assistant",
                            "content": "Interrupted answer",
                            "status": "streaming"
                        ]
                    ]
                ]
            ]
        ]
        try fixture.writeArchiveJSON(json)

        let archive = try fixture.store.load()
        #expect(archive.schemaVersion == AssistantConversationArchive.currentSchemaVersion)
        #expect(archive.conversations.count == 1)
        #expect(archive.conversations.first?.title == "Legacy")
        #expect(archive.conversations.first?.messages.first?.status == .stopped)
        #expect(archive.conversations.first?.messages.first?.citations.isEmpty == true)
    }

    @Test
    func retentionPrunesByAgeAndCount() throws {
        var retention = AssistantConversationRetention()
        retention.maximumConversations = 2
        retention.maximumAge = 3_600
        retention.maximumBytes = 4_000_000
        let fixture = try ConversationFixture(retention: retention)
        defer { fixture.cleanup() }

        let old = conversation(title: "Old", updatedAt: Date(timeIntervalSinceNow: -7_200))
        let middle = conversation(title: "Middle", updatedAt: Date(timeIntervalSinceNow: -60))
        let newest = conversation(title: "Newest", updatedAt: Date())

        let saved = try fixture.store.save(
            AssistantConversationArchive(
                lastOpenedConversationID: newest.id,
                conversations: [old, middle, newest]
            )
        )

        #expect(saved.conversations.map(\.title) == ["Newest", "Middle"])
        #expect(try fixture.store.load().conversations.map(\.title) == ["Newest", "Middle"])
    }

    @Test
    func retentionPrunesByByteSizeButKeepsAtLeastOneConversation() throws {
        var retention = AssistantConversationRetention()
        retention.maximumConversations = 10
        retention.maximumAge = 90 * 24 * 60 * 60
        retention.maximumBytes = 1
        let fixture = try ConversationFixture(retention: retention)
        defer { fixture.cleanup() }

        let saved = try fixture.store.save(
            AssistantConversationArchive(
                lastOpenedConversationID: nil,
                conversations: [
                    conversation(title: "First", updatedAt: Date().addingTimeInterval(-60)),
                    conversation(title: "Second")
                ]
            )
        )

        #expect(saved.conversations.count == 1)
        #expect(saved.conversations.first?.title == "Second")
    }

    @Test
    func failedAtomicWritePreservesTheExistingArchive() throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }

        let original = conversation(title: "Original")
        try fixture.store.save(
            AssistantConversationArchive(
                lastOpenedConversationID: original.id,
                conversations: [original]
            )
        )
        let originalData = try Data(contentsOf: fixture.store.archiveURL)

        let failingStore = AssistantConversationStore(
            workspaceURL: fixture.workspaceURL,
            storageRoot: fixture.storageRoot,
            writeData: { _, _ in throw TestWriteError.failed }
        )
        let replacement = conversation(title: "Replacement")

        #expect(throws: TestWriteError.self) {
            _ = try failingStore.save(
                AssistantConversationArchive(
                    lastOpenedConversationID: replacement.id,
                    conversations: [replacement]
                )
            )
        }

        #expect(try Data(contentsOf: fixture.store.archiveURL) == originalData)
        #expect(try fixture.store.load().conversations.first?.title == "Original")
    }

    private func makeRoundTripArchive() -> AssistantConversationArchive {
        let descriptor = AssistantContextDescriptor(
            item: AssistantContextItem(
                id: "R1",
                kind: .retrievedCode,
                title: "Loader.swift:4",
                relativePath: "Sources/Loader.swift",
                lineRange: 4...9,
                languageID: "swift",
                text: "secret source body",
                isTruncated: true
            )
        )
        let citation = AssistantCitation(
            id: "R1",
            title: "Loader.swift:4",
            relativePath: "Sources/Loader.swift",
            line: 4,
            endLine: 9
        )
        let createdAt = Date().addingTimeInterval(-60)
        let updatedAt = Date()
        let conversation = AssistantConversation(
            title: "Explain the loader",
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: [
                AssistantMessage(role: .user, content: "Explain the loader"),
                AssistantMessage(
                    role: .assistant,
                    content: "See [[source:R1]].",
                    status: .complete,
                    citations: [citation],
                    contextDescriptors: [descriptor]
                )
            ],
            providerID: "profile-id",
            providerName: "Local",
            model: "model-a"
        )
        return AssistantConversationArchive(
            lastOpenedConversationID: conversation.id,
            conversations: [conversation]
        )
    }

    private func conversation(title: String, updatedAt: Date = Date()) -> AssistantConversation {
        AssistantConversation(
            title: title,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            messages: [AssistantMessage(role: .user, content: title)]
        )
    }
}

private enum TestWriteError: Error {
    case failed
}
