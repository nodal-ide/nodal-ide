import SwiftUI

struct AssistantPanelView: View {
    @ObservedObject var session: AssistantSession

    @State private var pendingReset: ResetAction?

    var body: some View {
        VStack(spacing: 0) {
            AssistantHeaderView(
                session: session,
                onNewChat: requestNewChat,
                onClear: { pendingReset = .clear }
            )

            Divider()

            Group {
                if session.messages.isEmpty {
                    AssistantEmptyStateView(provider: session.provider) { prompt in
                        session.draft = prompt
                        session.requestComposerFocus()
                    }
                } else {
                    AssistantTranscriptView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            AssistantComposerView(session: session)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.requestComposerFocus()
        }
        .alert(item: $pendingReset) { action in
            switch action {
            case .newChat:
                return Alert(
                    title: Text("Start a new chat?"),
                    message: Text("The current conversation will be cleared."),
                    primaryButton: .destructive(Text("New Chat")) {
                        session.startNewConversation()
                    },
                    secondaryButton: .cancel()
                )
            case .clear:
                return Alert(
                    title: Text("Clear this conversation?"),
                    message: Text("This cannot be undone."),
                    primaryButton: .destructive(Text("Clear")) {
                        session.clearConversation()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant")
    }

    private func requestNewChat() {
        if session.messages.isEmpty {
            session.startNewConversation()
        } else {
            pendingReset = .newChat
        }
    }
}

struct AssistantInspectorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        AssistantPanelView(session: workspace.assistantSession)
    }
}

private enum ResetAction: String, Identifiable {
    case newChat
    case clear

    var id: String { rawValue }
}
