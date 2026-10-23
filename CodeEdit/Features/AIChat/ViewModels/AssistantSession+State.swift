import Foundation

extension AssistantSession {
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

    func copyTranscript() -> String {
        transcript
    }
}
