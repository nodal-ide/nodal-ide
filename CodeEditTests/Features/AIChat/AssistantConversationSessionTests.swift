@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct AssistantConversationSessionTests {
    @Test
    func sessionSavesAndRestoresTheLastConversation() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = makeSession()
        session.configureConversationHistory(store: fixture.store, enabled: true)
        session.draft = "Explain the loader"

        session.send()
        await AssistantTestData.waitForIdle(session)

        let saved = try fixture.store.load()
        #expect(saved.conversations.count == 1)
        #expect(saved.conversations.first?.title == "Explain the loader")
        #expect(saved.conversations.first?.messages.count == 2)
        #expect(saved.conversations.first?.messages.last?.status == .complete)
        #expect(session.activeConversationID == saved.lastOpenedConversationID)

        let restored = makeSession()
        restored.configureConversationHistory(store: fixture.store, enabled: true)

        #expect(restored.messages.count == 2)
        #expect(restored.activeConversationID == saved.lastOpenedConversationID)
        #expect(restored.conversations.count == 1)
    }

    @Test
    func historyOffSkipsWritesAndReenablingPersistsTheCurrentConversation() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = makeSession()
        session.configureConversationHistory(store: fixture.store, enabled: false)
        session.draft = "First"

        session.send()
        await AssistantTestData.waitForIdle(session)

        #expect(session.activeConversationID == nil)
        #expect(try fixture.store.load().conversations.isEmpty)

        session.setHistoryEnabled(true)
        #expect(session.activeConversationID != nil)
        #expect(try fixture.store.load().conversations.first?.messages.count == 2)

        session.setHistoryEnabled(false)
        session.draft = "Second"
        session.send()
        await AssistantTestData.waitForIdle(session)

        #expect(session.messages.count == 4)
        #expect(try fixture.store.load().conversations.first?.messages.count == 2)

        session.setHistoryEnabled(true)
        #expect(try fixture.store.load().conversations.first?.messages.count == 4)
    }

    @Test
    func newChatKeepsHistoryAndDeleteRemovesOnlyTheTarget() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = makeSession()
        session.configureConversationHistory(store: fixture.store, enabled: true)
        session.draft = "Keep this"

        session.send()
        await AssistantTestData.waitForIdle(session)
        let id = try #require(session.activeConversationID)
        session.startNewConversation()

        #expect(session.messages.isEmpty)
        #expect(session.activeConversationID == nil)
        #expect(session.conversations.count == 1)
        #expect(try fixture.store.load().conversations.count == 1)

        session.selectConversation(id)
        #expect(session.messages.count == 2)
        #expect(session.activeConversationID == id)

        session.deleteConversation(id)
        #expect(session.messages.isEmpty)
        #expect(session.activeConversationID == nil)
        #expect(session.conversations.isEmpty)
        #expect(try fixture.store.load().conversations.isEmpty)
    }

    @Test
    func renameAndClearAllArePersisted() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = makeSession()
        session.configureConversationHistory(store: fixture.store, enabled: true)
        session.draft = "Original title"

        session.send()
        await AssistantTestData.waitForIdle(session)
        let id = try #require(session.activeConversationID)
        session.renameConversation(id, title: "  Renamed  ")

        #expect(session.conversations.first?.title == "Renamed")
        #expect(try fixture.store.load().conversations.first?.title == "Renamed")

        session.clearAllConversationHistory()

        #expect(session.messages.isEmpty)
        #expect(session.conversations.isEmpty)
        #expect(session.activeConversationID == nil)
        #expect(try fixture.store.load().conversations.isEmpty)
    }

    @Test
    func clearConversationDeletesTheActiveHistoryEntry() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = makeSession()
        session.configureConversationHistory(store: fixture.store, enabled: true)
        session.draft = "Delete me"

        session.send()
        await AssistantTestData.waitForIdle(session)
        session.clearConversation()

        #expect(session.messages.isEmpty)
        #expect(session.conversations.isEmpty)
        #expect(try fixture.store.load().conversations.isEmpty)
    }

    @Test
    func clearingWhileHistoryIsOffStillDeletesTheActiveEntry() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = makeSession()
        session.configureConversationHistory(store: fixture.store, enabled: true)
        session.draft = "Delete after disabling history"

        session.send()
        await AssistantTestData.waitForIdle(session)
        session.setHistoryEnabled(false)
        #expect(try fixture.store.load().conversations.count == 1)

        session.clearConversation()

        #expect(session.messages.isEmpty)
        #expect(try fixture.store.load().conversations.isEmpty)
    }

    @Test
    func workspaceCloseStopsStreamingAndFlushesPartialContent() async throws {
        let fixture = try ConversationFixture()
        defer { fixture.cleanup() }
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 20_000_000, chunkSize: 4),
            provider: .mock
        )
        session.configureConversationHistory(store: fixture.store, enabled: true)
        session.draft = "Close while streaming"
        session.send()

        let deadline = ContinuousClock.now + .seconds(2)
        while session.messages.last?.content.isEmpty != false && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let partial = try #require(session.messages.last?.content)
        #expect(!partial.isEmpty)

        session.prepareForWorkspaceClose()

        #expect(!session.isStreaming)
        let saved = try fixture.store.load()
        #expect(saved.conversations.first?.messages.last?.status == .stopped)
        #expect(saved.conversations.first?.messages.last?.content == partial)
    }

    private func makeSession() -> AssistantSession {
        AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock
        )
    }
}
