import Foundation
import SwiftUI

#if DEBUG
private enum AssistantPreviewData {
    static let prompt = "Review this loading flow and suggest a cleaner structure."

    static let answer = """
    The current flow is close, but the view is doing two jobs: it owns presentation state and it starts \
    the request. I would move the request into a small session object and let the view forward intents.

    ### Suggested structure

    1. Keep the loading state in one place.
    2. Preserve the previous result while refreshing.
    3. Test cancellation independently from the view.

    ```swift
    @MainActor
    final class LoadingModel: ObservableObject {
        @Published private(set) var state: State = .idle

        func load() async {
            state = .loading
            do {
                state = .loaded(try await service.fetch())
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
    ```

    | State | Visible behavior |
    | --- | --- |
    | Loading | Keep the previous content |
    | Failed | Show a retry action |

    **Watch for:** overlapping requests and stale responses after cancellation.
    """

    static let userMessage = AssistantMessage(role: .user, content: prompt)
    static let assistantMessage = AssistantMessage(role: .assistant, content: answer)

    static func conversation(
        status: AssistantMessageStatus = .complete,
        content: String = answer,
        error: String? = nil
    ) -> [AssistantMessage] {
        [
            userMessage,
            AssistantMessage(
                role: .assistant,
                content: content,
                status: status,
                errorMessage: error
            )
        ]
    }
}

#Preview("Conversation") {
    AssistantPanelView(
        session: .preview(messages: AssistantPreviewData.conversation())
    )
    .frame(width: 410, height: 720)
}

#Preview("Streaming") {
    AssistantPanelView(
        session: .preview(
            messages: AssistantPreviewData.conversation(
                status: .streaming,
                content: "The current flow is close, but the view is doing two jobs: it owns presentation "
                    + "state and it starts the request.\n\nI would move the request into"
            ),
            phase: .streaming
        )
    )
    .frame(width: 410, height: 720)
}

#Preview("Stopped") {
    AssistantPanelView(
        session: .preview(
            messages: AssistantPreviewData.conversation(
                status: .stopped,
                content: "The current flow is close, but the view is doing two jobs."
            )
        )
    )
    .frame(width: 410, height: 720)
}

#Preview("Failed") {
    AssistantPanelView(
        session: .preview(
            messages: AssistantPreviewData.conversation(
                status: .failed,
                content: "The current flow is close,",
                error: "The provider closed the connection before the response completed."
            )
        )
    )
    .frame(width: 410, height: 720)
}

#Preview("Empty") {
    AssistantPanelView(session: .preview())
        .frame(width: 410, height: 720)
}

#Preview("No Provider") {
    AssistantPanelView(session: .preview(provider: nil))
        .frame(width: 410, height: 720)
}
#endif
