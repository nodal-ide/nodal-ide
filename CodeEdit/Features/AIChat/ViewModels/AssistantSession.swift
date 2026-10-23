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

    private let transport: any AssistantTransport
    private var streamTask: Task<Void, Never>?
    private var activeResponseID: UUID?

    init(
        transport: any AssistantTransport = MockAssistantTransport(),
        provider: AssistantProvider? = .mock,
        messages: [AssistantMessage] = [],
        phase: Phase = .idle
    ) {
        self.transport = transport
        self.provider = provider
        self.messages = messages
        self.phase = phase
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
        !messages.isEmpty || !draft.isEmpty
    }

    var destinationLabel: String {
        guard let provider else {
            return "No provider configured"
        }
        return "\(provider.name) · \(provider.connection.label)"
    }

    var transcript: String {
        messages.map { message in
            let name = message.isUser ? "You" : "Assistant"
            return "\(name)\n\(message.content)"
        }
        .joined(separator: "\n\n")
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        draft = ""
        messages.append(AssistantMessage(role: .user, content: prompt))
        contentRevision += 1
        let conversation = messages
        let assistantMessage = AssistantMessage(role: .assistant, content: "", status: .streaming)
        messages.append(assistantMessage)
        contentRevision += 1
        startStreaming(prompt: prompt, conversation: conversation, responseID: assistantMessage.id)
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
        startStreaming(prompt: prompt, conversation: conversation, responseID: response.id)
    }

    func startNewConversation() {
        cancelStreaming()
        messages = []
        draft = ""
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

    private func startStreaming(prompt: String, conversation: [AssistantMessage], responseID: UUID) {
        phase = .streaming
        activeResponseID = responseID
        let request = AssistantRequest(prompt: prompt, conversation: conversation)

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
