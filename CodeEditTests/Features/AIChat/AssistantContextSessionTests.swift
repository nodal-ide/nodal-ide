@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct AssistantContextSessionTests {
    @Test
    func sessionAttachesContextAndClearsItOnNewConversation() {
        let provider = AssistantTestContextProvider()
        provider.selection = AssistantTestData.selectionSnapshot()
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )

        #expect(session.attachCurrentSelection())
        #expect(session.contextItems.count == 1)
        #expect(session.contextItems.first?.kind == .selection)
        #expect(session.hasSelectionContext)
        #expect(session.canStartNewChat)

        session.startNewConversation()

        #expect(session.contextItems.isEmpty)
        #expect(!session.hasSelectionContext)
    }

    @Test
    func sessionFallsBackToActiveFileWhenThereIsNoSelection() {
        let provider = AssistantTestContextProvider()
        provider.snapshot = AssistantTestData.workspaceSnapshot(rootName: "Workspace")
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )

        #expect(session.addCurrentSelectionOrActiveFile())
        #expect(session.contextItems.first?.kind == .activeFile)
    }

    @Test
    func sessionRequiresConfirmationForSensitiveSelection() {
        let provider = AssistantTestContextProvider()
        provider.selection = AssistantTestData.selectionSnapshot(relativePath: ".env", secret: true)
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )

        #expect(session.attachCurrentSelection())
        #expect(session.contextItems.isEmpty)
        #expect(session.pendingSensitiveContext?.isSensitive == true)

        session.confirmSensitiveContext()

        #expect(session.pendingSensitiveContext == nil)
        #expect(session.contextItems.count == 1)
        #expect(session.contextItems.first?.isSensitive == true)

        session.removeContextItem(id: AssistantContextBuilder.selectionID)
        #expect(session.contextItems.isEmpty)
    }

    @Test
    func sessionSendsSystemInstructionsAndBoundedContext() async throws {
        let transport = AssistantTestRecordingTransport()
        let provider = AssistantTestContextProvider()
        provider.selection = AssistantTestData.selectionSnapshot()
        provider.snapshot = AssistantTestData.workspaceSnapshot(rootName: "Workspace")
        let session = AssistantSession(transport: transport, provider: .mock, contextProvider: provider)
        session.attachCurrentSelection()
        session.draft = "Explain the selection"

        session.send()
        await AssistantTestData.waitForIdle(session)

        let request = try #require(transport.requests.first)
        let context = try #require(request.context)
        #expect(request.systemInstructions == AssistantPromptComposer.systemInstructions)
        #expect(context.items.contains { $0.kind == .selection })
        #expect(context.items.contains { $0.kind == .project })
        #expect(context.items.first { $0.kind == .selection }?.text.contains("let value = 2") == true)
    }

    @Test
    func previewShowsTheSameRedactedTextThatWillBeSent() {
        let provider = AssistantTestContextProvider()
        provider.selection = AssistantTestData.selectionSnapshot()
        provider.snapshot = AssistantTestData.workspaceSnapshot(rootName: "Workspace")
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )
        session.attachCurrentSelection()

        let preview = session.contextPreview

        #expect(preview.contextText.contains("let value = 2"))
        #expect(preview.contextText.contains("Sources/Active.swift"))
        #expect(preview.contextText.contains(NSHomeDirectory()) == false)
        #expect(preview.items.contains { $0.kind == .selection })
        #expect(preview.items.contains { $0.kind == .project })
    }

    @Test
    func defaultContextIncludesDiagnosticsAndTasksWithoutDuplicates() {
        let provider = AssistantTestContextProvider()
        provider.snapshot = AssistantTestData.workspaceSnapshot(rootName: "Workspace")
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )

        let packet = session.makeContextPacket()

        #expect(packet.items.filter { $0.kind == .diagnostics }.count == 1)
        #expect(packet.items.filter { $0.kind == .tasks }.count == 1)
        #expect(packet.items.first { $0.kind == .diagnostics }?.text.contains("active error") == true)
    }

    @Test
    func defaultContextCanBeDisabledAndExplicitItemsAreNotDuplicated() {
        let provider = AssistantTestContextProvider()
        provider.snapshot = AssistantTestData.workspaceSnapshot(rootName: "Workspace")
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )
        session.configureDefaultContext(includeDiagnostics: false, includeTasks: false)
        #expect(session.makeContextPacket().items.contains { $0.kind == .diagnostics } == false)
        #expect(session.makeContextPacket().items.contains { $0.kind == .tasks } == false)

        #expect(session.addDiagnostics())
        #expect(session.makeContextPacket().items.filter { $0.kind == .diagnostics }.count == 1)

        session.configureDefaultContext(includeDiagnostics: true, includeTasks: true)
        #expect(session.makeContextPacket().items.filter { $0.kind == .diagnostics }.count == 1)
    }

    @Test
    func removingSelectionClearsStaleIndicator() {
        let provider = AssistantTestContextProvider()
        provider.selection = AssistantTestData.selectionSnapshot()
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 0),
            provider: .mock,
            contextProvider: provider
        )
        session.attachCurrentSelection()

        session.removeContextItem(id: AssistantContextBuilder.selectionID)

        #expect(!session.selectionNeedsRefresh)
        #expect(session.contextItems.isEmpty)
    }
}
