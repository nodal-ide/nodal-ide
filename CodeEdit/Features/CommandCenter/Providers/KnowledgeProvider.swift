//
//  KnowledgeProvider.swift
//  CodeEdit
//
//  Command Center provider: knowledge base entries.
//

import Foundation

@MainActor
final class KnowledgeProvider: CommandCenterProvider {
    let id = "knowledge"
    let category: CommandCenterCategory = .knowledge
    let priority = 40

    func search(_ query: String) async -> [CommandCenterItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let results = KnowledgeSearchIndex.shared.search(
            trimmed,
            in: KnowledgeRegistry.shared.sources,
            limitPerSource: 10
        )
        return results.map { result in
            CommandCenterItem(
                id: "kb:\(result.id)",
                title: result.title,
                subtitle: "\(result.sourceTitle) · \(result.path)",
                systemImage: "book",
                category: .knowledge,
                kind: .route("knowledge:\(result.sourceID):\(result.path)")
            )
        }
    }
}
