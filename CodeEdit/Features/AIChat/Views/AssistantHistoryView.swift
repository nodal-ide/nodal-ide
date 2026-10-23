import SwiftUI

struct AssistantHistoryView: View {
    @ObservedObject var session: AssistantSession
    let onNewChat: () -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var renameTarget: AssistantConversation?
    @State private var renameText = ""
    @State private var showingRename = false
    @State private var deleteTarget: AssistantConversation?
    @State private var showingClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 330, height: 390)
        .alert("Rename Conversation", isPresented: $showingRename) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Rename") {
                if let renameTarget {
                    session.renameConversation(renameTarget.id, title: renameText)
                }
                renameTarget = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a short title for this conversation.")
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    session.deleteConversation(deleteTarget.id)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("This removes the conversation from this workspace and cannot be undone.")
        }
        .confirmationDialog(
            "Clear all conversation history?",
            isPresented: $showingClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                session.clearAllConversationHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every saved conversation in this workspace will be removed. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
                onNewChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("New Chat")
            .accessibilityLabel("New Chat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if session.conversations.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("No saved conversations")
                    .font(.system(size: 11.5, weight: .medium))
                Text("Conversations are saved locally for this workspace.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(session.conversations) { conversation in
                        row(conversation)
                    }
                }
                .padding(7)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice = session.historyNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: session.isHistoryEnabled ? "lock" : "pause.circle")
                    .font(.system(size: 9))
                Text(
                    session.isHistoryEnabled
                        ? "Saved locally for this workspace"
                        : "History is off — new messages won't be saved"
                )
                .font(.system(size: 9.5))
                .lineLimit(2)
                Spacer(minLength: 6)
                Button("Clear All") {
                    showingClearAll = true
                }
                .font(.system(size: 9.5))
                .buttonStyle(.plain)
                .foregroundStyle(session.conversations.isEmpty ? Color.secondary : Color.red)
                .disabled(session.conversations.isEmpty)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ conversation: AssistantConversation) -> some View {
        Button {
            session.selectConversation(conversation.id)
            dismiss()
        } label: {
            rowLabel(conversation)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renameTarget = conversation
                renameText = conversation.title
                showingRename = true
            }
            Button("Delete", role: .destructive) {
                deleteTarget = conversation
            }
        }
        .accessibilityLabel("\(conversation.title), \(messageCountLabel(conversation.messages.count))")
        .accessibilityHint("Restores this conversation")
    }

    private func rowLabel(_ conversation: AssistantConversation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                rowMetadata(conversation)
            }

            Spacer(minLength: 4)

            if session.activeConversationID == conversation.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            session.activeConversationID == conversation.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium)
        )
        .contentShape(Rectangle())
    }

    private func rowMetadata(_ conversation: AssistantConversation) -> some View {
        HStack(spacing: 5) {
            Text(conversation.updatedAt, style: .relative)
            Text("·")
            Text(messageCountLabel(conversation.messages.count))
            if let model = conversation.model, !model.isEmpty {
                Text("·")
                Text(model)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.secondary)
    }

    private var headerSubtitle: String {
        guard !session.conversations.isEmpty else { return "Local only" }
        return "\(session.conversations.count) saved locally"
    }

    private func messageCountLabel(_ count: Int) -> String {
        count == 1 ? "1 message" : "\(count) messages"
    }
}
