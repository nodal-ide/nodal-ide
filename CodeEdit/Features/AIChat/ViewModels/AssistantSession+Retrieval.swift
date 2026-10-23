import Foundation

extension AssistantSession {
    func contextWithRetrieval(
        base: AssistantContextPacket,
        prompt: String
    ) async -> AssistantContextPacket {
        guard retrievalEnabled, let retrievalProvider else { return base }
        let workspace = contextProvider?.workspaceSnapshot()
        let selection = contextItems.first { $0.kind == .selection }
        let active = contextItems.first { $0.kind == .activeFile }
        let query = AssistantRetrievalQuery(
            text: prompt,
            selectionText: selection?.text,
            selectionPath: selection?.relativePath,
            activePath: active?.relativePath ?? workspace?.activeFile?.relativePath,
            openPaths: Set(workspace?.openFiles.map(\.relativePath) ?? []),
            language: workspace?.project.language,
            frameworks: workspace?.project.frameworks ?? []
        )
        let result = await retrievalProvider.retrieve(query)
        guard !result.isEmpty else { return base }
        let items = base.items.filter { $0.kind != .project }
            + AssistantContextBuilder.retrievalItems(from: result)
            + AssistantContextBuilder.knowledgeItems(from: result)
        return AssistantContextBuilder.packet(
            items: items,
            project: workspace?.project,
            budget: AssistantContextBudget()
        )
    }

    func makeContextPreviewWithRetrieval() async -> AssistantContextPreview {
        let base = makeContextPacket()
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let packet = await contextWithRetrieval(base: base, prompt: prompt)
        return AssistantContextPreview(
            systemInstructions: AssistantPromptComposer.systemInstructions,
            contextText: AssistantPromptComposer.contextText(for: packet),
            items: packet.items,
            estimatedTokens: packet.estimatedTokens,
            warnings: uniqueWarnings(packet),
            omittedTitles: packet.omittedTitles
        )
    }

    private func uniqueWarnings(_ packet: AssistantContextPacket) -> [String] {
        var seen = Set<String>()
        return (packet.warnings + packet.items.flatMap(\.warnings)).filter {
            seen.insert($0).inserted
        }
    }

    func configureRetrieval(_ provider: (any AssistantRetrievalProviding)?) {
        retrievalProvider?.stop()
        retrievalProvider?.setStatusHandler(nil)
        retrievalProvider = provider
        guard let provider else {
            retrievalStatus = .idle
            return
        }
        provider.setStatusHandler { [weak self] status in
            self?.retrievalStatus = status
        }
        if retrievalEnabled {
            provider.start()
        }
    }

    func setRetrievalEnabled(_ enabled: Bool) {
        retrievalEnabled = enabled
        guard enabled else {
            retrievalProvider?.stop()
            return
        }
        retrievalProvider?.start()
    }

    func rebuildRetrievalIndex() {
        retrievalProvider?.rebuild()
    }

    func clearRetrievalIndex() {
        retrievalProvider?.clear()
    }

    func stopRetrieval() {
        retrievalProvider?.stop()
    }

    func openCitation(_ citation: AssistantCitation) {
        if citationOpener?(citation) == true {
            return
        }
        if citation.knowledgeSourceID != nil {
            citationNotice = "The knowledge page \"\(citation.title)\" is no longer available."
        } else if citation.relativePath.isEmpty {
            citationNotice = "This citation does not point to an available source."
        } else {
            citationNotice = "Could not open \(citation.relativePath). The file may have moved or been deleted."
        }
    }

    func dismissCitationNotice() {
        citationNotice = nil
    }
}
