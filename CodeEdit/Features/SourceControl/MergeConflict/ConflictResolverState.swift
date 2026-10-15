//
//  ConflictResolverState.swift
//  CodeEdit
//
//  Shared state for the merge-conflict resolver panel.
//

import Combine
import Foundation

@MainActor
final class ConflictResolverState: ObservableObject {
    static let shared = ConflictResolverState()

    @Published var fileURL: URL?
    @Published var conflicts: [ConflictBlock] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var markedResolved = false

    private weak var manager: SourceControlManager?
    private var content = ""

    private init() {}

    func load(url: URL, manager: SourceControlManager) {
        self.fileURL = url
        self.manager = manager
        self.markedResolved = false
        reload()
    }

    func reload() {
        guard let fileURL else { return }
        isLoading = true
        errorMessage = nil

        guard let content = readContent(fileURL) else {
            errorMessage = "Could not read the file."
            conflicts = []
            isLoading = false
            return
        }
        self.content = content
        conflicts = ConflictParser.parse(content).conflicts
        isLoading = false
    }

    func resolve(_ conflict: ConflictBlock, as resolution: ConflictResolution) {
        guard let fileURL else { return }
        let updated = ConflictResolver.applying(resolution, to: conflict, in: content)
        guard updated != content else { return }
        writeContent(updated, to: fileURL)
        content = updated
        conflicts = ConflictParser.parse(updated).conflicts
    }

    func markResolved() {
        guard let fileURL, let manager else { return }
        Task {
            try? await manager.add([fileURL])
            markedResolved = true
        }
    }

    // MARK: - Open document / disk access

    private func readContent(_ url: URL) -> String? {
        if let document = codeDocument(for: url), let content = document.content?.string {
            return content
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func writeContent(_ content: String, to url: URL) {
        if let document = codeDocument(for: url), let storage = document.content {
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: content)
            document.updateChangeCount(.changeDone)
        } else {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func codeDocument(for url: URL) -> CodeFileDocument? {
        CodeEditDocumentController.shared.documents
            .compactMap { $0 as? CodeFileDocument }
            .first { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }
    }
}
