import Foundation

struct AssistantContextBudget: Equatable, Sendable {
    var maximumContextTokens = 6_144
    var selectionTokens = 2_600
    var activeFileTokens = 2_400
    var diagnosticsTokens = 700
    var taskTokens = 500
    var openFilesTokens = 350
    var projectTokens = 250
    var retrievalTokens = 1_400
    var knowledgeTokens = 700

    func fit(_ items: [AssistantContextItem]) -> AssistantContextPacket {
        let ordered = items.sorted { lhs, rhs in
            priority(for: lhs.kind) < priority(for: rhs.kind)
        }

        var included: [AssistantContextItem] = []
        var omitted: [String] = []
        var warnings: [String] = []
        var remaining = maximumContextTokens
        var usedByKind: [AssistantContextItem.Kind: Int] = [:]

        for var item in ordered {
            let categoryRemaining = cap(for: item.kind) - usedByKind[item.kind, default: 0]
            let itemCap = min(categoryRemaining, remaining)
            let tokens = estimateTokens(item.text)

            if tokens <= itemCap {
                included.append(item)
                remaining -= tokens
                usedByKind[item.kind, default: 0] += tokens
                continue
            }

            if itemCap >= 80 {
                item.text = truncate(item.text, to: max(0, itemCap * 4))
                item.isTruncated = true
                item.warnings.append("\(item.title) was truncated to fit the context limit.")
                included.append(item)
                let used = min(itemCap, estimateTokens(item.text))
                remaining -= used
                usedByKind[item.kind, default: 0] += used
                warnings.append("\(item.title) was truncated to fit the context limit.")
            } else {
                omitted.append(item.title)
                warnings.append("\(item.title) was omitted because the context limit was reached.")
            }
        }

        return AssistantContextPacket(
            items: included,
            estimatedTokens: maximumContextTokens - remaining,
            warnings: unique(warnings),
            omittedTitles: omitted
        )
    }

    func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    private func cap(for kind: AssistantContextItem.Kind) -> Int {
        switch kind {
        case .selection:
            return selectionTokens
        case .activeFile:
            return activeFileTokens
        case .diagnostics:
            return diagnosticsTokens
        case .tasks:
            return taskTokens
        case .openFiles:
            return openFilesTokens
        case .project:
            return projectTokens
        case .retrievedCode:
            return retrievalTokens
        case .knowledge:
            return knowledgeTokens
        }
    }

    private func priority(for kind: AssistantContextItem.Kind) -> Int {
        switch kind {
        case .selection:
            return 0
        case .activeFile:
            return 1
        case .project:
            return 2
        case .diagnostics:
            return 3
        case .tasks:
            return 4
        case .retrievedCode:
            return 5
        case .knowledge:
            return 6
        case .openFiles:
            return 7
        }
    }

    private func truncate(_ text: String, to maximumCharacters: Int) -> String {
        guard maximumCharacters > 1, text.count > maximumCharacters else { return text }
        let markerReserve = min(80, maximumCharacters / 2)
        let contentBudget = max(2, maximumCharacters - markerReserve)
        let headCount = contentBudget * 2 / 3
        let tailCount = max(0, contentBudget - headCount)
        let head = text.prefix(headCount)
        let tail = text.suffix(tailCount)
        let removed = text.count - head.count - tail.count
        let marker = "\n… [truncated \(removed) characters] …\n"
        let result = "\(head)\(marker)\(tail)"
        return String(result.prefix(maximumCharacters))
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
