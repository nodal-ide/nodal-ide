import Foundation

@MainActor
extension AssistantSession {
    var hasContextItems: Bool {
        !contextItems.isEmpty
    }

    var hasSelectionContext: Bool {
        contextItems.contains { $0.kind == .selection }
    }

    var destinationLabel: String {
        guard let provider else {
            return "No provider configured"
        }
        return "\(provider.name) · \(provider.connection.label)"
    }

    var destinationHost: String {
        provider?.host ?? "No destination"
    }

    var contextPreview: AssistantContextPreview {
        makeContextPreview()
    }

    func configureContextProvider(_ provider: any AssistantContextProviding) {
        contextProvider = provider
    }

    @discardableResult
    func attachCurrentSelection() -> Bool {
        guard let snapshot = contextProvider?.currentSelection() else { return false }
        return attachSelection(snapshot)
    }

    @discardableResult
    func attachSelection(_ snapshot: AssistantSelectionSnapshot) -> Bool {
        guard let item = AssistantContextBuilder.selectionItem(from: snapshot) else { return false }
        if item.isSensitive {
            pendingSensitiveContext = item
            pendingSelectionSnapshot = snapshot
            return true
        }
        commit(item, selectionSnapshot: snapshot)
        return true
    }

    @discardableResult
    func addCurrentSelectionOrActiveFile() -> Bool {
        if attachCurrentSelection() {
            return true
        }
        return addActiveFile()
    }

    @discardableResult
    func addActiveFile() -> Bool {
        guard let snapshot = contextProvider?.workspaceSnapshot(),
              let item = AssistantContextBuilder.activeFileItem(from: snapshot)
        else { return false }
        attach(item)
        return true
    }

    @discardableResult
    func addOpenFiles() -> Bool {
        guard let snapshot = contextProvider?.workspaceSnapshot(),
              let item = AssistantContextBuilder.openFilesItem(from: snapshot)
        else { return false }
        attach(item)
        return true
    }

    @discardableResult
    func addDiagnostics() -> Bool {
        guard let snapshot = contextProvider?.workspaceSnapshot(),
              let item = AssistantContextBuilder.diagnosticsItem(from: snapshot)
        else { return false }
        attach(item)
        return true
    }

    @discardableResult
    func addTasks() -> Bool {
        guard let snapshot = contextProvider?.workspaceSnapshot(),
              let item = AssistantContextBuilder.tasksItem(from: snapshot)
        else { return false }
        attach(item)
        return true
    }

    func refreshSelection() {
        guard let snapshot = contextProvider?.currentSelection(),
              let item = AssistantContextBuilder.selectionItem(from: snapshot)
        else { return }
        if item.isSensitive {
            pendingSensitiveContext = item
            pendingSelectionSnapshot = snapshot
            return
        }
        commit(item, selectionSnapshot: snapshot)
    }

    func removeContextItem(id: String) {
        contextItems.removeAll { $0.id == id }
        if id == AssistantContextBuilder.selectionID {
            attachedSelectionSnapshot = nil
            selectionNeedsRefresh = false
            selectionCheckTask?.cancel()
        }
    }

    func clearContext() {
        contextItems = []
        attachedSelectionSnapshot = nil
        selectionNeedsRefresh = false
        pendingSensitiveContext = nil
        pendingSelectionSnapshot = nil
        selectionCheckTask?.cancel()
    }

    func confirmSensitiveContext() {
        guard let item = pendingSensitiveContext else { return }
        let selection = pendingSelectionSnapshot
        pendingSensitiveContext = nil
        pendingSelectionSnapshot = nil
        commit(item, selectionSnapshot: selection)
    }

    func cancelSensitiveContext() {
        pendingSensitiveContext = nil
        pendingSelectionSnapshot = nil
    }

    var transcript: String {
        messages.map { message in
            let name = message.isUser ? "You" : "Assistant"
            return "\(name)\n\(message.content)"
        }
        .joined(separator: "\n\n")
    }

    private func attach(_ item: AssistantContextItem) {
        if item.isSensitive {
            pendingSensitiveContext = item
            pendingSelectionSnapshot = nil
            return
        }
        commit(item, selectionSnapshot: nil)
    }

    private func commit(
        _ item: AssistantContextItem,
        selectionSnapshot: AssistantSelectionSnapshot?
    ) {
        contextItems.removeAll { $0.id == item.id }
        contextItems.append(item)
        if item.kind == .selection {
            attachedSelectionSnapshot = selectionSnapshot
            selectionNeedsRefresh = false
            selectionCheckTask?.cancel()
        }
    }

    func makeContextPacket() -> AssistantContextPacket {
        let project = contextProvider?.workspaceSnapshot()?.project
        return AssistantContextBuilder.packet(items: contextItems, project: project)
    }

    func makeContextPreview() -> AssistantContextPreview {
        let project = contextProvider?.workspaceSnapshot()?.project
        return AssistantContextBuilder.preview(items: contextItems, project: project)
    }

    func scheduleSelectionCheck() {
        guard attachedSelectionSnapshot != nil else { return }
        selectionCheckTask?.cancel()
        selectionCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.compareCurrentSelection()
        }
    }

    private func compareCurrentSelection() {
        guard let attachedSelectionSnapshot,
              let current = contextProvider?.currentSelection()
        else { return }
        selectionNeedsRefresh = current != attachedSelectionSnapshot
    }

}
