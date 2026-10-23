import Foundation

extension AssistantSession {
    func configureConversationHistory(
        store: AssistantConversationStore?,
        enabled: Bool
    ) {
        conversationStore = store
        isHistoryEnabled = enabled
        guard let store else {
            conversations = []
            activeConversationID = nil
            return
        }

        do {
            let archive = try store.load()
            conversations = archive.conversations
            if enabled,
               messages.isEmpty,
               let id = archive.lastOpenedConversationID,
               let conversation = conversations.first(where: { $0.id == id }) {
                restore(conversation)
            } else {
                activeConversationID = nil
            }
        } catch {
            conversations = []
            activeConversationID = nil
            historyNotice = error.localizedDescription
        }
    }

    func startNewConversation() {
        if isStreaming {
            stop()
        } else {
            persistCurrentConversation()
        }
        replaceConversationState(messages: [], activeConversationID: nil)
        clearContext()
        persistHistorySelection()
        finishConversationTransition()
    }

    func clearConversation() {
        let activeID = activeConversationID
        replaceConversationState(messages: [], activeConversationID: nil)
        if let activeID {
            conversations.removeAll { $0.id == activeID }
        }
        clearContext()
        saveHistoryArchive(force: true)
        finishConversationTransition()
    }

    func setHistoryEnabled(_ enabled: Bool) {
        guard isHistoryEnabled != enabled else { return }
        if enabled {
            isHistoryEnabled = true
            persistCurrentConversation()
        } else {
            persistCurrentConversation()
            isHistoryEnabled = false
        }
    }

    func selectConversation(_ id: UUID) {
        guard id != activeConversationID,
              let selected = conversations.first(where: { $0.id == id })
        else { return }

        if isStreaming {
            stop()
        } else {
            persistCurrentConversation()
        }
        replaceConversationState(messages: selected.messages, activeConversationID: selected.id)
        clearContext()
        persistHistorySelection()
        finishConversationTransition()
    }

    func renameConversation(_ id: UUID, title: String) {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == id })
        else { return }
        conversations[index].title = trimmed
        conversations[index].updatedAt = Date()
        saveHistoryArchive(force: true)
    }

    func deleteConversation(_ id: UUID) {
        if id == activeConversationID {
            replaceConversationState(messages: [], activeConversationID: nil)
        }
        conversations.removeAll { $0.id == id }
        saveHistoryArchive(force: true)
    }

    func clearAllConversationHistory() {
        replaceConversationState(messages: [], activeConversationID: nil)
        conversations = []
        clearContext()

        do {
            try conversationStore?.clear()
            historyNotice = nil
        } catch {
            historyNotice = "Couldn't clear conversation history: \(error.localizedDescription)"
        }
        requestComposerFocus()
    }

    func flushConversationHistory() {
        persistCurrentConversation()
    }

    func prepareForWorkspaceClose() {
        if isStreaming {
            stop()
        } else {
            flushConversationHistory()
        }
    }

    func dismissHistoryNotice() {
        historyNotice = nil
    }

    func persistCurrentConversation() {
        guard isHistoryEnabled, conversationStore != nil, !messages.isEmpty else { return }
        let now = Date()

        if let id = activeConversationID,
           let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].messages = messages
            conversations[index].updatedAt = now
            conversations[index].providerID = provider?.id
            conversations[index].providerName = provider?.name
            conversations[index].model = provider?.model
        } else {
            let conversation = AssistantConversation(
                title: AssistantConversation.defaultTitle(from: messages),
                createdAt: now,
                updatedAt: now,
                messages: messages,
                providerID: provider?.id,
                providerName: provider?.name,
                model: provider?.model
            )
            activeConversationID = conversation.id
            conversations.insert(conversation, at: 0)
        }

        saveHistoryArchive()
    }

    func persistHistorySelection() {
        saveHistoryArchive()
    }

    func setContextDescriptors(_ items: [AssistantContextItem], for messageID: UUID) {
        applyContextDescriptors(items.map(AssistantContextDescriptor.init), to: messageID)
    }

    private func saveHistoryArchive(force: Bool = false) {
        guard isHistoryEnabled || force, let conversationStore else { return }
        let archive = AssistantConversationArchive(
            lastOpenedConversationID: activeConversationID,
            conversations: conversations
        )

        do {
            let saved = try conversationStore.save(archive)
            conversations = saved.conversations
            if let activeConversationID,
               !saved.conversations.contains(where: { $0.id == activeConversationID }) {
                self.activeConversationID = nil
            }
            historyNotice = nil
        } catch {
            historyNotice = "Couldn't save conversation history: \(error.localizedDescription)"
        }
    }

    private func restore(_ conversation: AssistantConversation) {
        replaceConversationState(
            messages: conversation.messages,
            activeConversationID: conversation.id
        )
    }
}
