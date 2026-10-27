// swiftlint:disable file_length
import Foundation

// swiftlint:disable:next type_body_length
actor AssistantRetrievalIndex {
    private struct IndexedChunk {
        let chunk: AssistantRetrievalChunk
        let termFrequencies: [String: Int]
        let length: Int
    }

    private struct WorkspaceFile {
        let url: URL
        let relativePath: String
        let languageID: String
        let record: AssistantRetrievalFileRecord
    }

    private let rootURL: URL
    private let storageDirectory: URL
    private let snapshotURL: URL
    private var chunks: [AssistantRetrievalChunk] = []
    private var indexedChunks: [IndexedChunk] = []
    private var documentFrequency: [String: Int] = [:]
    private var averageLength = 0.0
    private var fileRecords: [String: AssistantRetrievalFileRecord] = [:]
    /// Tokenizing every chunk is the expensive part of a build, so the inverted index is rebuilt at
    /// most once per mutation of ``chunks`` instead of once per entry point.
    private var invertedIndexIsStale = true

    init(rootURL: URL, storageRoot: URL? = nil) {
        let standardizedRoot = rootURL.standardizedFileURL
        self.rootURL = standardizedRoot
        let base = storageRoot
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                .map { $0.appending(path: "CodeEdit/AssistantRetrieval", directoryHint: .isDirectory) }
            ?? FileManager.default.temporaryDirectory
        let workspaceKey = AssistantRetrievalChunker.stableHash(
            standardizedRoot.path(percentEncoded: false)
        )
        let directory = base.appending(path: workspaceKey, directoryHint: .isDirectory)
        self.storageDirectory = directory
        self.snapshotURL = directory.appending(path: "index-v\(AssistantRetrievalSnapshot.schemaVersion).json")
    }

    func prepare(progress: @Sendable (Int, Int) async -> Void) async -> AssistantRetrievalStatus {
        loadSnapshot()
        return await refresh(progress: progress)
    }

    func rebuild(progress: @Sendable (Int, Int) async -> Void) async -> AssistantRetrievalStatus {
        chunks = []
        indexedChunks = []
        documentFrequency = [:]
        averageLength = 0
        fileRecords = [:]
        invertedIndexIsStale = true
        removeSnapshot()
        return await refresh(progress: progress)
    }

    func clear() {
        chunks = []
        indexedChunks = []
        documentFrequency = [:]
        averageLength = 0
        fileRecords = [:]
        invertedIndexIsStale = true
        removeSnapshot()
        try? FileManager.default.removeItem(at: storageDirectory)
    }

    func search(_ query: AssistantRetrievalQuery, limit: Int = 10) -> [AssistantRetrievedExcerpt] {
        guard !chunks.isEmpty else { return [] }
        ensureInvertedIndex()
        let weights = queryWeights(for: query)
        guard !weights.isEmpty else { return [] }

        let queryText = query.text.lowercased()
        let documentCount = Double(indexedChunks.count)
        var scored: [(IndexedChunk, Double)] = []
        scored.reserveCapacity(indexedChunks.count)

        for document in indexedChunks {
            let score = bm25Score(document: document, weights: weights, documentCount: documentCount)
            guard score > 0 else { continue }
            scored.append(
                (
                    document,
                    score * boost(for: document.chunk, query: query, queryText: queryText, weights: weights)
                )
            )
        }

        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            if lhs.0.chunk.relativePath != rhs.0.chunk.relativePath {
                return lhs.0.chunk.relativePath < rhs.0.chunk.relativePath
            }
            return lhs.0.chunk.startLine < rhs.0.chunk.startLine
        }

        return deduplicate(scored, limit: limit)
    }

    private func queryWeights(for query: AssistantRetrievalQuery) -> [String: Double] {
        var weights = AssistantRetrievalTokenizer.weightedTerms(in: query.text, weight: 1)
        if let selectionText = query.selectionText {
            merge(
                AssistantRetrievalTokenizer.weightedTerms(in: selectionText, weight: 1.8),
                into: &weights
            )
        }
        if let activePath = query.activePath {
            merge(
                AssistantRetrievalTokenizer.weightedTerms(in: activePath, weight: 0.9),
                into: &weights
            )
        }
        if let selectionPath = query.selectionPath {
            merge(
                AssistantRetrievalTokenizer.weightedTerms(in: selectionPath, weight: 0.9),
                into: &weights
            )
        }
        for framework in query.frameworks {
            merge(
                AssistantRetrievalTokenizer.weightedTerms(in: framework, weight: 0.4),
                into: &weights
            )
        }
        return weights
    }

    private func bm25Score(
        document: IndexedChunk,
        weights: [String: Double],
        documentCount: Double
    ) -> Double {
        let kOne = 1.2
        let lengthWeight = 0.75
        var score = 0.0
        for (term, weight) in weights {
            let frequency = Double(document.termFrequencies[term] ?? 0)
            guard frequency > 0 else { continue }
            let frequencyInDocuments = Double(documentFrequency[term] ?? 0)
            let inverseDocumentFrequency = log(
                1 + (documentCount - frequencyInDocuments + 0.5) / (frequencyInDocuments + 0.5)
            )
            let normalization = frequency
                + kOne * (1 - lengthWeight + lengthWeight * Double(document.length) / max(averageLength, 1))
            score += weight * inverseDocumentFrequency * frequency * (kOne + 1) / normalization
        }
        return score
    }

    private func deduplicate(
        _ scored: [(IndexedChunk, Double)],
        limit: Int
    ) -> [AssistantRetrievedExcerpt] {
        var results: [AssistantRetrievedExcerpt] = []
        var perFileCount: [String: Int] = [:]
        var acceptedByFile: [String: [AssistantRetrievalChunk]] = [:]

        for (document, score) in scored {
            guard results.count < limit else { break }
            let chunk = document.chunk
            guard perFileCount[chunk.relativePath, default: 0] < 3 else { continue }
            let existing = acceptedByFile[chunk.relativePath, default: []]
            guard !existing.contains(where: { overlaps($0, chunk) }) else { continue }
            guard !existing.contains(where: { $0.contentHash == chunk.contentHash }) else { continue }

            perFileCount[chunk.relativePath, default: 0] += 1
            acceptedByFile[chunk.relativePath, default: []].append(chunk)
            results.append(
                AssistantRetrievedExcerpt(
                    id: chunk.id,
                    relativePath: chunk.relativePath,
                    languageID: chunk.languageID,
                    startLine: chunk.startLine,
                    endLine: chunk.endLine,
                    text: chunk.text,
                    score: score
                )
            )
        }

        return results
    }

    private func refresh(progress: @Sendable (Int, Int) async -> Void) async -> AssistantRetrievalStatus {
        let files = await Task.detached(priority: .utility) { [rootURL] in
            Self.collectFiles(rootURL: rootURL)
        }.value

        guard !Task.isCancelled else {
            return .ready(indexedFiles: fileRecords.count, chunkCount: chunks.count)
        }

        let existingByPath = Dictionary(grouping: chunks, by: \.relativePath)
        var newChunks: [AssistantRetrievalChunk] = []
        var newRecords: [String: AssistantRetrievalFileRecord] = [:]
        newChunks.reserveCapacity(chunks.count)

        for (offset, file) in files.enumerated() {
            if Task.isCancelled {
                return .ready(indexedFiles: fileRecords.count, chunkCount: chunks.count)
            }

            newRecords[file.relativePath] = file.record
            if fileRecords[file.relativePath] == file.record,
               let existing = existingByPath[file.relativePath] {
                newChunks.append(contentsOf: existing)
            } else {
                newChunks.append(contentsOf: index(file: file))
            }

            if offset % 8 == 0 || offset == files.count - 1 {
                await progress(offset + 1, files.count)
            }
        }

        chunks = newChunks
        fileRecords = newRecords
        invertedIndexIsStale = true
        ensureInvertedIndex()
        saveSnapshot()
        return .ready(indexedFiles: fileRecords.count, chunkCount: chunks.count)
    }

    private func index(file: WorkspaceFile) -> [AssistantRetrievalChunk] {
        guard file.record.size <= AssistantRetrievalFileFilter.maximumFileSize,
              let data = try? Data(contentsOf: file.url, options: [.mappedIfSafe]),
              !AssistantRetrievalFileFilter.isBinary(data),
              let text = AssistantRetrievalFileFilter.decode(data)
        else { return [] }

        let redacted = SecretRedactor.redact(text).text
        return AssistantRetrievalChunker.chunks(
            text: redacted,
            relativePath: file.relativePath,
            languageID: file.languageID
        )
    }

    private func rebuildInvertedIndex() {
        var indexed: [IndexedChunk] = []
        indexed.reserveCapacity(chunks.count)
        var frequencies: [String: Int] = [:]
        var totalLength = 0

        for chunk in chunks {
            let terms = AssistantRetrievalTokenizer.terms(in: chunk.text)
            let termFrequencies = Dictionary(grouping: terms, by: { $0 }).mapValues(\.count)
            indexed.append(
                IndexedChunk(
                    chunk: chunk,
                    termFrequencies: termFrequencies,
                    length: terms.count
                )
            )
            totalLength += terms.count
            for term in termFrequencies.keys {
                frequencies[term, default: 0] += 1
            }
        }

        indexedChunks = indexed
        documentFrequency = frequencies
        averageLength = indexed.isEmpty ? 0 : Double(totalLength) / Double(indexed.count)
        invertedIndexIsStale = false
    }

    private func ensureInvertedIndex() {
        guard invertedIndexIsStale else { return }
        rebuildInvertedIndex()
    }

    private func boost(
        for chunk: AssistantRetrievalChunk,
        query: AssistantRetrievalQuery,
        queryText: String,
        weights: [String: Double]
    ) -> Double {
        var boost = 1.0
        if chunk.relativePath == query.selectionPath {
            boost += 2.5
        } else if chunk.relativePath == query.activePath {
            boost += 1.8
        } else if query.openPaths.contains(chunk.relativePath) {
            boost += 1.2
        }

        if let language = query.language,
           !language.isEmpty,
           chunk.languageID == language {
            boost += 0.25
        }

        let fileName = (chunk.relativePath as NSString).lastPathComponent.lowercased()
        if !fileName.isEmpty, queryText.contains(fileName) {
            boost += 2.0
        }

        let pathTerms = Set(AssistantRetrievalTokenizer.terms(in: chunk.relativePath))
        let overlap = pathTerms.intersection(weights.keys).count
        boost += min(1.8, Double(overlap) * 0.4)
        return boost
    }

    private func overlaps(_ lhs: AssistantRetrievalChunk, _ rhs: AssistantRetrievalChunk) -> Bool {
        let start = max(lhs.startLine, rhs.startLine)
        let end = min(lhs.endLine, rhs.endLine)
        guard start <= end else { return false }
        let overlapLength = end - start + 1
        let shorter = min(lhs.endLine - lhs.startLine + 1, rhs.endLine - rhs.startLine + 1)
        return shorter > 0 && Double(overlapLength) / Double(shorter) > 0.5
    }

    private func merge(_ addition: [String: Double], into target: inout [String: Double]) {
        for (key, value) in addition {
            target[key, default: 0] += value
        }
    }

    private func loadSnapshot() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(AssistantRetrievalSnapshot.self, from: data),
              snapshot.schemaVersion == AssistantRetrievalSnapshot.schemaVersion
        else {
            removeSnapshot()
            return
        }

        chunks = snapshot.chunks.filter { !SecretRedactor.isSecretPath($0.relativePath) }
        fileRecords = snapshot.files
        invertedIndexIsStale = true
    }

    private func saveSnapshot() {
        let snapshot = AssistantRetrievalSnapshot(files: fileRecords, chunks: chunks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: snapshotURL, options: [.atomic])
        } catch {
            removeSnapshot()
        }
    }

    private func removeSnapshot() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    private nonisolated static func collectFiles(rootURL: URL) -> [WorkspaceFile] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var files: [WorkspaceFile] = []
        for case let url as URL in enumerator {
            if Task.isCancelled {
                break
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory == true
            let relativePath = AssistantPathUtilities.relativePath(for: url, root: rootURL)
            if values?.isSymbolicLink == true
                || AssistantRetrievalFileFilter.isIgnored(
                    relativePath: relativePath,
                    isDirectory: isDirectory
                ) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }
            if let file = workspaceFile(
                url: url,
                relativePath: relativePath,
                values: values,
                isDirectory: isDirectory
            ) {
                files.append(file)
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private nonisolated static func workspaceFile(
        url: URL,
        relativePath: String,
        values: URLResourceValues?,
        isDirectory: Bool
    ) -> WorkspaceFile? {
        guard !isDirectory,
              values?.isRegularFile == true,
              !AssistantRetrievalFileFilter.isSecret(relativePath: relativePath),
              let size = values?.fileSize,
              size <= AssistantRetrievalFileFilter.maximumFileSize
        else { return nil }
        return WorkspaceFile(
            url: url,
            relativePath: relativePath,
            languageID: AssistantRetrievalFileFilter.languageID(for: relativePath),
            record: AssistantRetrievalFileRecord(
                modificationTime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: size
            )
        )
    }
}
