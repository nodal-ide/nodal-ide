import Foundation

struct AssistantLanguageZone: Equatable, Hashable, Sendable {
    let languageID: String
    let parentLanguageID: String?
    let sourceKey: String?
    let depth: Int
}

struct AssistantSelectionRange: Equatable, Sendable {
    let lineRange: ClosedRange<Int>
    let text: String
    let zones: [AssistantLanguageZone]
}

struct AssistantSelectionSnapshot: Equatable, Sendable {
    let fileURL: URL
    let relativePath: String
    let languageID: String
    let ranges: [AssistantSelectionRange]
    let isSecretPath: Bool

    var lineRange: ClosedRange<Int>? {
        guard let first = ranges.first?.lineRange else { return nil }
        return ranges.dropFirst().reduce(first) { partial, range in
            min(partial.lowerBound, range.lineRange.lowerBound)...max(partial.upperBound, range.lineRange.upperBound)
        }
    }

    var text: String {
        ranges.map(\.text).joined(separator: "\n\n")
    }
}

struct AssistantContextItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case selection
        case activeFile
        case openFiles
        case diagnostics
        case tasks
        case project
        case retrievedCode
        case knowledge

        var label: String {
            switch self {
            case .selection:
                return "Selection"
            case .activeFile:
                return "Active file"
            case .openFiles:
                return "Open files"
            case .diagnostics:
                return "Diagnostics"
            case .tasks:
                return "Tasks"
            case .project:
                return "Project"
            case .retrievedCode:
                return "Workspace excerpt"
            case .knowledge:
                return "Knowledge"
            }
        }

        var symbolName: String {
            switch self {
            case .selection:
                return "text.cursor"
            case .activeFile:
                return "doc.text"
            case .openFiles:
                return "doc.on.doc"
            case .diagnostics:
                return "exclamationmark.triangle"
            case .tasks:
                return "terminal"
            case .project:
                return "folder"
            case .retrievedCode:
                return "doc.text.magnifyingglass"
            case .knowledge:
                return "book.closed"
            }
        }
    }

    let id: String
    let kind: Kind
    var title: String
    var relativePath: String?
    var lineRange: ClosedRange<Int>?
    var languageID: String?
    var knowledgeSourceID: String?
    var zones: [AssistantLanguageZone]
    var text: String
    var isTruncated: Bool
    var isSensitive: Bool
    var redactionCount: Int
    var warnings: [String]

    init(
        id: String,
        kind: Kind,
        title: String,
        relativePath: String? = nil,
        lineRange: ClosedRange<Int>? = nil,
        languageID: String? = nil,
        knowledgeSourceID: String? = nil,
        zones: [AssistantLanguageZone] = [],
        text: String,
        isTruncated: Bool = false,
        isSensitive: Bool = false,
        redactionCount: Int = 0,
        warnings: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.relativePath = relativePath
        self.lineRange = lineRange
        self.languageID = languageID
        self.knowledgeSourceID = knowledgeSourceID
        self.zones = zones
        self.text = text
        self.isTruncated = isTruncated
        self.isSensitive = isSensitive
        self.redactionCount = redactionCount
        self.warnings = warnings
    }

    var lineLabel: String? {
        guard let lineRange else { return nil }
        if lineRange.lowerBound == lineRange.upperBound {
            return "line \(lineRange.lowerBound)"
        }
        return "lines \(lineRange.lowerBound)–\(lineRange.upperBound)"
    }
}

struct AssistantContextPacket: Equatable, Sendable {
    var items: [AssistantContextItem]
    var estimatedTokens: Int
    var warnings: [String]
    var omittedTitles: [String]

    static let empty = AssistantContextPacket(items: [], estimatedTokens: 0, warnings: [], omittedTitles: [])
}

struct AssistantContextPreview: Equatable, Sendable {
    let systemInstructions: String
    let contextText: String
    let items: [AssistantContextItem]
    let estimatedTokens: Int
    let warnings: [String]
    let omittedTitles: [String]

    var isTruncated: Bool {
        items.contains(where: \.isTruncated) || !omittedTitles.isEmpty
    }

    var secretWarningCount: Int {
        items.filter(\.isSensitive).count
    }
}

struct AssistantProjectSnapshot: Equatable, Sendable {
    let name: String
    let rootName: String
    let language: String
    let frameworks: [String]
}

struct AssistantFileSnapshot: Equatable, Sendable {
    let relativePath: String
    let languageID: String
    let text: String
    let isActive: Bool
}

struct AssistantDiagnosticSnapshot: Equatable, Sendable {
    let relativePath: String
    let line: Int?
    let column: Int?
    let severity: String
    let message: String
    let ruleID: String?
    let languageID: String?
}

struct AssistantTaskSnapshot: Equatable, Sendable {
    let name: String
    let command: String
    let status: String
}

struct AssistantWorkspaceSnapshot: Equatable, Sendable {
    let project: AssistantProjectSnapshot
    let activeFile: AssistantFileSnapshot?
    let openFiles: [AssistantFileSnapshot]
    let diagnostics: [AssistantDiagnosticSnapshot]
    let tasks: [AssistantTaskSnapshot]
}
