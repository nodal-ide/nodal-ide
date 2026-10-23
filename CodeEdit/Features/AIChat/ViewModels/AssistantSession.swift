import CodeEditTextView
import Combine
import Foundation

@MainActor
final class AssistantSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case streaming

        var isStreaming: Bool {
            self == .streaming
        }
    }

    static let maximumDraftLength = 12_000

    @Published private(set) var messages: [AssistantMessage]
    @Published var draft = "" {
        didSet {
            if draft.count > Self.maximumDraftLength {
                draft = String(draft.prefix(Self.maximumDraftLength))
            }
        }
    }
    @Published private(set) var phase: Phase
    @Published private(set) var provider: AssistantProvider?
    @Published private(set) var focusRequest = 0
    @Published private(set) var contentRevision = 0
    @Published var contextItems: [AssistantContextItem] = []
    @Published var selectionNeedsRefresh = false
    @Published var pendingSensitiveContext: AssistantContextItem?

    private let transport: any AssistantTransport
    var contextProvider: (any AssistantContextProviding)?
    private var streamTask: Task<Void, Never>?
    private var activeResponseID: UUID?
    var attachedSelectionSnapshot: AssistantSelectionSnapshot?
    var pendingSelectionSnapshot: AssistantSelectionSnapshot?
    var selectionCheckTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        transport: any AssistantTransport = MockAssistantTransport(),
        provider: AssistantProvider? = .mock,
        messages: [AssistantMessage] = [],
        phase: Phase = .idle,
        contextProvider: (any AssistantContextProviding)? = nil
    ) {
        self.transport = transport
        self.provider = provider
        self.messages = messages
        self.phase = phase
        self.contextProvider = contextProvider

        NotificationCenter.default.publisher(for: TextSelectionManager.selectionChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSelectionCheck()
            }
            .store(in: &cancellables)
    }

    var isStreaming: Bool {
        phase.isStreaming
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && provider?.isUsable == true
            && !isStreaming
    }

    var canStartNewChat: Bool {
        !messages.isEmpty || !draft.isEmpty || !contextItems.isEmpty
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        draft = ""
        messages.append(AssistantMessage(role: .user, content: prompt))
        contentRevision += 1
        let conversation = messages
        let packet = makeContextPacket()
        let assistantMessage = AssistantMessage(role: .assistant, content: "", status: .streaming)
        messages.append(assistantMessage)
        contentRevision += 1
        startStreaming(
            prompt: prompt,
            conversation: conversation,
            context: packet,
            responseID: assistantMessage.id
        )
    }

    func stop() {
        guard isStreaming else { return }
        let responseID = activeResponseID
        streamTask?.cancel()
        streamTask = nil
        activeResponseID = nil
        phase = .idle
        markMessage(responseID, status: .stopped)
        requestComposerFocus()
    }

    func retry(_ messageID: UUID) {
        guard !isStreaming,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].role == .assistant,
              messages[index].status == .failed || messages[index].status == .stopped
        else { return }

        guard let userIndex = messages[..<index].lastIndex(where: { $0.role == .user }) else { return }
        let prompt = messages[userIndex].content
        let conversation = Array(messages[..<index])
        messages.removeSubrange(index...)
        contentRevision += 1
        let response = AssistantMessage(role: .assistant, content: "", status: .streaming)
        messages.append(response)
        contentRevision += 1
        startStreaming(
            prompt: prompt,
            conversation: conversation,
            context: makeContextPacket(),
            responseID: response.id
        )
    }

    func startNewConversation() {
        cancelStreaming()
        messages = []
        draft = ""
        clearContext()
        contentRevision += 1
        phase = .idle
        requestComposerFocus()
    }

    func clearConversation() {
        startNewConversation()
    }

    func requestComposerFocus() {
        focusRequest += 1
    }

    func copyTranscript() -> String {
        transcript
    }

    private func startStreaming(
        prompt: String,
        conversation: [AssistantMessage],
        context: AssistantContextPacket,
        responseID: UUID
    ) {
        phase = .streaming
        activeResponseID = responseID
        let request = AssistantRequest(
            prompt: prompt,
            conversation: conversation,
            systemInstructions: AssistantPromptComposer.systemInstructions,
            context: context.items.isEmpty ? nil : context
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in self.transport.stream(request) {
                    try Task.checkCancellation()
                    guard self.activeResponseID == responseID else { return }
                    if case .delta(let text) = event {
                        self.append(text, to: responseID)
                    }
                }
                guard self.activeResponseID == responseID else { return }
                self.finish(responseID)
            } catch is CancellationError {
                guard self.activeResponseID == responseID else { return }
                self.markMessage(responseID, status: .stopped)
                self.completeActiveRequest()
            } catch {
                guard self.activeResponseID == responseID else { return }
                self.fail(responseID, error: error)
            }
        }
    }

    private func append(_ text: String, to messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        var updated = messages
        updated[index].content += text
        messages = updated
        contentRevision += 1
    }

    private func finish(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            completeActiveRequest()
            return
        }

        var updated = messages
        if updated[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated[index].status = .failed
            updated[index].errorMessage = "The assistant returned an empty response."
        } else {
            updated[index].status = .complete
        }
        messages = updated
        contentRevision += 1
        completeActiveRequest()
    }

    private func fail(_ messageID: UUID, error: Error) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            completeActiveRequest()
            return
        }

        var updated = messages
        updated[index].status = .failed
        updated[index].errorMessage = error.localizedDescription
        messages = updated
        contentRevision += 1
        completeActiveRequest()
    }

    private func markMessage(_ messageID: UUID?, status: AssistantMessageStatus) {
        guard let messageID,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].status == .streaming
        else { return }

        var updated = messages
        updated[index].status = status
        messages = updated
        contentRevision += 1
    }

    private func completeActiveRequest() {
        streamTask = nil
        activeResponseID = nil
        phase = .idle
        requestComposerFocus()
    }

    private func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        activeResponseID = nil
    }

    static func preview(
        messages: [AssistantMessage] = [],
        provider: AssistantProvider? = .mock,
        phase: Phase = .idle,
        scenario: MockAssistantScenario = .standard
    ) -> AssistantSession {
        AssistantSession(
            transport: MockAssistantTransport(scenario: scenario, chunkDelayNanoseconds: 20_000_000),
            provider: provider,
            messages: messages,
            phase: phase
        )
    }
}
