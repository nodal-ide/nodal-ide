import Foundation

struct AssistantRetrievalQuery: Equatable, Sendable {
    var text: String
    var selectionText: String?
    var selectionPath: String?
    var activePath: String?
    var openPaths: Set<String> = []
    var language: String?
    var frameworks: [String] = []

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectionText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
}

struct AssistantRetrievedExcerpt: Identifiable, Equatable, Sendable {
    let id: String
    let relativePath: String
    let languageID: String
    let startLine: Int
    let endLine: Int
    let text: String
    let score: Double
}

struct AssistantKnowledgeExcerpt: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let pagePath: String
    let title: String
    let text: String
}

struct AssistantRetrievalResult: Equatable, Sendable {
    var code: [AssistantRetrievedExcerpt] = []
    var knowledge: [AssistantKnowledgeExcerpt] = []
    var warnings: [String] = []

    static let empty = AssistantRetrievalResult()

    var isEmpty: Bool {
        code.isEmpty && knowledge.isEmpty
    }
}

enum AssistantRetrievalStatus: Equatable, Sendable {
    case idle
    case indexing(completed: Int, total: Int)
    case ready(indexedFiles: Int, chunkCount: Int)
    case failed(String)

    var isIndexing: Bool {
        if case .indexing = self {
            return true
        }
        return false
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    var label: String {
        switch self {
        case .idle:
            return "Workspace index not started"
        case let .indexing(completed, total):
            guard total > 0 else { return "Indexing workspace…" }
            return "Indexing workspace \(completed)/\(total)"
        case let .ready(indexedFiles, chunkCount):
            return "\(indexedFiles) files · \(chunkCount) excerpts indexed"
        case .failed(let message):
            return "Workspace index failed: \(message)"
        }
    }
}

struct AssistantRetrievalChunk: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let relativePath: String
    let languageID: String
    let startLine: Int
    let endLine: Int
    let contentHash: String
    let text: String
}

struct AssistantRetrievalFileRecord: Codable, Equatable, Sendable {
    let modificationTime: TimeInterval
    let size: Int
}

struct AssistantRetrievalSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let files: [String: AssistantRetrievalFileRecord]
    let chunks: [AssistantRetrievalChunk]

    init(
        schemaVersion: Int = AssistantRetrievalSnapshot.schemaVersion,
        files: [String: AssistantRetrievalFileRecord],
        chunks: [AssistantRetrievalChunk]
    ) {
        self.schemaVersion = schemaVersion
        self.files = files
        self.chunks = chunks
    }
}
