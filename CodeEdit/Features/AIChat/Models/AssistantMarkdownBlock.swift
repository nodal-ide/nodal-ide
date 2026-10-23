import Foundation

enum AssistantMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case numberedList([String])
    case quote(String)
    case code(language: String?, content: String)
    case divider
    case table(headers: [String], rows: [[String]])
}

enum AssistantMarkdownParser {
    private enum ListKind {
        case bullet
        case numbered
    }

    static func parse(_ source: String) -> [AssistantMarkdownBlock] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [AssistantMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isFence(trimmed) {
                let result = parseCode(lines: lines, start: index)
                blocks.append(result.block)
                index = result.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isDivider(trimmed) {
                blocks.append(.divider)
                index += 1
                continue
            }

            if let table = parseTable(lines: lines, start: index) {
                blocks.append(table.block)
                index = table.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let result = parseQuote(lines: lines, start: index)
                blocks.append(result.block)
                index = result.nextIndex
                continue
            }

            if let list = parseList(lines: lines, start: index) {
                blocks.append(list.block)
                index = list.nextIndex
                continue
            }

            let result = parseParagraph(lines: lines, start: index)
            blocks.append(result.block)
            index = result.nextIndex
        }

        return blocks
    }

    private static func parseCode(
        lines: [String],
        start: Int
    ) -> (block: AssistantMarkdownBlock, nextIndex: Int) {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        let language = String(opening.dropFirst(3))
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init)
        var content: [String] = []
        var index = start + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if isFence(trimmed) {
                index += 1
                break
            }
            content.append(lines[index])
            index += 1
        }

        return (
            .code(
                language: language?.isEmpty == false ? language : nil,
                content: content.joined(separator: "\n")
            ),
            index
        )
    }

    private static func parseHeading(_ line: String) -> AssistantMarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }

        let content = line.dropFirst(level)
        guard content.first == " " else { return nil }
        return .heading(level: level, text: content.trimmingCharacters(in: .whitespaces))
    }

    private static func isFence(_ line: String) -> Bool {
        line.hasPrefix("```")
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" }
    }

    private static func parseQuote(
        lines: [String],
        start: Int
    ) -> (block: AssistantMarkdownBlock, nextIndex: Int) {
        var content: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            content.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }

        return (.quote(content.joined(separator: " ")), index)
    }

    private static func parseList(
        lines: [String],
        start: Int
    ) -> (block: AssistantMarkdownBlock, nextIndex: Int)? {
        let first = lines[start]
        guard let kind = listKind(first) else { return nil }

        var items: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                break
            }

            if let item = listItem(line, kind: kind) {
                items.append(item)
                index += 1
                continue
            }

            let isIndented = line.first == " " || line.first == "\t"
            if isIndented, !items.isEmpty, !startsBlock(lines: lines, at: index) {
                items[items.count - 1] += " " + trimmed
                index += 1
                continue
            }

            break
        }

        let block: AssistantMarkdownBlock = kind == .bullet ? .bulletList(items) : .numberedList(items)
        return (block, index)
    }

    private static func parseParagraph(
        lines: [String],
        start: Int
    ) -> (block: AssistantMarkdownBlock, nextIndex: Int) {
        var content: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || startsBlock(lines: lines, at: index) {
                break
            }
            content.append(trimmed)
            index += 1
        }

        return (.paragraph(content.joined(separator: " ")), index)
    }

    private static func parseTable(
        lines: [String],
        start: Int
    ) -> (block: AssistantMarkdownBlock, nextIndex: Int)? {
        guard start + 1 < lines.count,
              lines[start].contains("|"),
              let headers = tableCells(lines[start]),
              !headers.isEmpty
        else { return nil }

        let separatorCells = tableCells(lines[start + 1])
        guard let separatorCells,
              separatorCells.count == headers.count,
              separatorCells.allSatisfy(isTableSeparator)
        else { return nil }

        var rows: [[String]] = []
        var index = start + 2

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, line.contains("|"), let cells = tableCells(line) else { break }
            rows.append(normalizedCells(cells, count: headers.count))
            index += 1
        }

        return (.table(headers: headers, rows: rows), index)
    }
}

private extension AssistantMarkdownParser {
    private static func tableCells(_ line: String) -> [String]? {
        var value = line.trimmingCharacters(in: .whitespaces)
        guard value.contains("|") else { return nil }
        if value.hasPrefix("|") {
            value.removeFirst()
        }
        if value.hasSuffix("|") {
            value.removeLast()
        }
        let cells = value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableSeparator(_ cell: String) -> Bool {
        let value = cell.replacingOccurrences(of: ":", with: "")
        return !value.isEmpty && value.allSatisfy { $0 == "-" }
    }

    private static func normalizedCells(_ cells: [String], count: Int) -> [String] {
        if cells.count == count {
            return cells
        }
        if cells.count < count {
            return cells + Array(repeating: "", count: count - cells.count)
        }
        return Array(cells.prefix(count))
    }

    private static func startsBlock(lines: [String], at index: Int) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || isFence(trimmed) || parseHeading(trimmed) != nil || isDivider(trimmed) {
            return true
        }
        if trimmed.hasPrefix(">") || listKind(lines[index]) != nil {
            return true
        }
        if index + 1 < lines.count,
           lines[index].contains("|"),
           let cells = tableCells(lines[index]),
           let separators = tableCells(lines[index + 1]),
           cells.count == separators.count,
           separators.allSatisfy(isTableSeparator) {
            return true
        }
        return false
    }

    private static func listKind(_ line: String) -> ListKind? {
        for kind in [ListKind.bullet, .numbered] where listItem(line, kind: kind) != nil {
            return kind
        }
        return nil
    }

    private static func listItem(_ line: String, kind: ListKind) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        switch kind {
        case .bullet:
            guard trimmed.count >= 2, "-*+".contains(trimmed.first!) else { return nil }
            let content = trimmed.dropFirst()
            guard content.first == " " else { return nil }
            return content.trimmingCharacters(in: .whitespaces)
        case .numbered:
            let digits = trimmed.prefix(while: { $0.isNumber })
            guard !digits.isEmpty else { return nil }
            let rest = trimmed.dropFirst(digits.count)
            guard rest.first == "." || rest.first == ")" else { return nil }
            let content = rest.dropFirst()
            guard content.first == " " else { return nil }
            return content.trimmingCharacters(in: .whitespaces)
        }
    }
}
