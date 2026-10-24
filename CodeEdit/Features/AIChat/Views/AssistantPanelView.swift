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
                    AssistantEmptyStateView(provider: session.provider) { suggestion in
                        attachContext(for: suggestion)
                        session.draft = suggestion.prompt
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
                    message: Text(newChatMessage),
                    primaryButton: .destructive(Text("New Chat")) {
                        session.onNewChat()
                    },
                    secondaryButton: .cancel()
                )
            case .clear:
                return Alert(
                    title: Text("Clear this conversation?"),
                    message: Text(clearMessage),
                    primaryButton: .destructive(Text("Clear")) {
                        session.onClear()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .alert(
            "Source unavailable",
            isPresented: Binding(
                get: { session.citationNotice != nil },
                set: { if !$0 { session.dismissCitationNotice() } }
            )
        ) {
            Button("OK") {
                session.dismissCitationNotice()
            }
        } message: {
            Text(session.citationNotice ?? "")
        }
        .alert(
            "Conversation history",
            isPresented: Binding(
                get: { session.historyNotice != nil },
                set: { if !$0 { session.dismissHistoryNotice() } }
            )
        ) {
            Button("OK") {
                session.dismissHistoryNotice()
            }
        } message: {
            Text(session.historyNotice ?? "")
        }
        .alert(item: pendingSensitiveBinding) { item in
            Alert(
                title: Text("Attach sensitive context?"),
                message: Text(sensitiveMessage(for: item)),
                primaryButton: .destructive(Text("Attach")) {
                    session.confirmSensitiveContext()
                },
                secondaryButton: .cancel {
                    session.cancelSensitiveContext()
                }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant")
    }

    private var pendingSensitiveBinding: Binding<AssistantContextItem?> {
        Binding(
            get: { session.pendingSensitiveContext },
            set: { value in
                if value == nil {
                    session.cancelSensitiveContext()
                }
            }
        )
    }

    private func sensitiveMessage(for item: AssistantContextItem) -> String {
        var message = "\(item.title) looks like it may contain secrets. "
            + "Common secret patterns have been redacted, but review the context preview before sending."
        if !item.warnings.isEmpty {
            message += "\n\n" + item.warnings.joined(separator: "\n")
        }
        return message
    }

    private var newChatMessage: String {
        session.isHistoryEnabled
            ? "The current conversation will be saved in History."
            : "The current conversation will be cleared because history is off."
    }

    private var clearMessage: String {
        session.isHistoryEnabled
            ? "This conversation will be removed from History. This cannot be undone."
            : "This cannot be undone."
    }

    private func attachContext(for suggestion: AssistantSuggestion) {
        switch suggestion.context {
        case .selection:
            _ = session.addCurrentSelectionOrActiveFile()
        case .fileIssues:
            _ = session.addActiveFile()
            _ = session.addDiagnostics()
        case .activeFile:
            _ = session.addActiveFile()
        case .openFiles:
            _ = session.addOpenFiles()
        }
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
        AssistantPanelView(
                    session: workspace.assistantSession,
                )
    }
}

private enum ResetAction: String, Identifiable {
    case newChat
    case clear

    var id: String { rawValue }
}
