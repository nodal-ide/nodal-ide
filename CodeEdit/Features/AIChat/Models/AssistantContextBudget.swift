import Foundation

struct AssistantContextBudget: Equatable, Sendable {
    var maximumContextTokens = 6_144
    var selectionTokens = 2_600
    var activeFileTokens = 2_400
    var diagnosticsTokens = 700
    var taskTokens = 500
    var openFilesTokens = 350
    var projectTokens = 250

    func fit(_ items: [AssistantContextItem]) -> AssistantContextPacket {
        let ordered = items.sorted { lhs, rhs in
            priority(for: lhs.kind) < priority(for: rhs.kind)
        }

        var included: [AssistantContextItem] = []
        var omitted: [String] = []
        var warnings: [String] = []
        var remaining = maximumContextTokens

        for var item in ordered {
            let itemCap = min(cap(for: item.kind), remaining)
            let tokens = estimateTokens(item.text)

            if tokens <= itemCap {
                included.append(item)
                remaining -= tokens
                continue
            }

            if itemCap >= 80 {
                item.text = truncate(item.text, to: max(0, itemCap * 4))
                item.isTruncated = true
                item.warnings.append("\(item.title) was truncated to fit the context limit.")
                included.append(item)
                let used = min(itemCap, estimateTokens(item.text))
                remaining -= used
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
        }
    }

    private func priority(for kind: AssistantContextItem.Kind) -> Int {
        switch kind {
        case .selection:
            return 0
        case .project:
            return 1
        case .activeFile:
            return 2
        case .diagnostics:
            return 3
        case .tasks:
            return 4
        case .openFiles:
            return 5
        }
    }

    private func truncate(_ text: String, to maximumCharacters: Int) -> String {
        guard maximumCharacters > 1, text.count > maximumCharacters else { return text }
        let headCount = maximumCharacters * 2 / 3
        let tailCount = max(0, maximumCharacters - headCount)
        let head = text.prefix(headCount)
        let tail = text.suffix(tailCount)
        let removed = text.count - head.count - tail.count
        return "\(head)\n… [truncated \(removed) characters] …\n\(tail)"
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
