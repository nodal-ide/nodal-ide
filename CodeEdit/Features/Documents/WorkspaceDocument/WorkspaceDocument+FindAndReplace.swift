//
//  WorkspaceDocument+FindAndReplace.swift
//  CodeEdit
//
//  Created by Tommy Ludwig on 02.01.24.
//

import Foundation
import AppKit

extension WorkspaceDocument.SearchState {
    /// Performs a search and replace operation in a collection of files based on the provided query.
    ///
    /// - Parameters:
    ///   - query: The search query to look for in the files.
    ///   - replacingTerm: The term to replace the matched query with.
    ///
    /// - Important: This function relies on an indexer and assumes that it has been previously set.
    /// If the indexer is not available, the function will return early.
    /// Also make sure to flush any pending changes to the index before calling this function.
    func findAndReplace(query: String, replacingTerm: String) async throws {
        await setStatus(.replacing)
        let searchQuery = getSearchTerm(query)
        guard let indexer = indexer else { return }

        var errorCount: Int = 0, updatedFilesCount: Int = 0
        let asyncController = SearchIndexer.AsyncManager(index: indexer)

        let searchStream = await asyncController.search(query: searchQuery, 20)

        for try await result in searchStream {
            await withTaskGroup(of: Bool.self) { taskGroup in
                for file in result.results {
                    taskGroup.addTask {
                        do {
                            return try await self.replaceOccurrencesInFile(
                                fileURL: file.url,
                                query: query,
                                replacingTerm: replacingTerm
                            )
                        } catch {
                            // TODO: Write log; issue number: #0000
                            return false
                        }
                    }
                }

                for await taskGroupResults in taskGroup {
                    if taskGroupResults {
                        updatedFilesCount += 1
                    } else {
                        errorCount += 1
                    }
                }
            }
        }

        // Display the replacing results to the user
        if updatedFilesCount == 0 && errorCount == 0 {
            // No results where found
            await setStatus(.failed(errorMessage: "No files in the workspace matched: \(query)"))
        } else if updatedFilesCount == 0 && errorCount > 0 {
            // All files failed to updated
            await setStatus(
                .failed(
                    errorMessage: "All files failed to update. (\(errorCount)) " +
                    "errors occurred. Check logs for more information"
                )
            )
        } else if updatedFilesCount > 0 && errorCount > 0 {
            // Some files updated successfully, some failed
            await setStatus(
                .failed(
                    errorMessage: "\(updatedFilesCount) successfully updated, " +
                    "\(errorCount) errors occurred. Please check logs for more information."
                )
            )
        } else {
            // Each files updated successfully
            await setStatus(.replaced(updatedFiles: updatedFilesCount))
        }
    }

    /// Replaces occurrences of a specified query with a given replacement term in a file.
    ///
    /// If the file is open in the workspace, its **in-memory document** is updated (so the editor reflects the
    /// change and unsaved edits are preserved); otherwise the file is rewritten on disk.
    ///
    /// - Returns: `true` if the file's content changed.
    @MainActor
    func replaceOccurrencesInFile(
        fileURL: URL,
        query: String,
        replacingTerm: String
    ) async throws -> Bool {
        if let file = workspace.workspaceFileManager?.getFile(fileURL.path)
                    ?? workspace.workspaceFileManager?.getFile(fileURL.relativePath),
           let document = file.fileDocument,
           let content = document.content {
            let original = content.string
            let updated = original.replacingOccurrences(
                of: query,
                with: replacingTerm,
                options: replaceOptions
            )
            guard updated != original else { return false }
            content.replaceCharacters(in: NSRange(location: 0, length: content.length), with: updated)
            document.updateChangeCount(.changeDone)
            return true
        }

        let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
        let updatedContent = fileContent.replacingOccurrences(
            of: query,
            with: replacingTerm,
            options: replaceOptions
        )
        guard updatedContent != fileContent else { return false }
        try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }

    /// Replaces a specified range of text within a file with a new string.
    ///
    /// - Parameters:
    ///   - file: The URL of the file to be modified.
    ///   - searchTerm: The string to be replaced within the specified range.
    ///   - replacingTerm: The string to replace the specified searchTerm.
    ///   - keywordRange: The range within which the replacement should occur.
    ///
    /// - Note: This function  can be utilised for two specific use cases:
    ///         1. To replace a particular occurrence of a string within a file,
    ///         provide the range of the keyword to be replaced.
    ///         2. To replace all occurrences of the string within the file,
    ///         pass the start and end index covering the entire range.
    func replaceRange(
        file: URL,
        searchTerm: String,
        replacingTerm: String,
        keywordRange: Range<String.Index>
    ) {
        guard let fileContent = try? String(contentsOf: file, encoding: .utf8) else {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "An error occurred while reading file contents of: \(file)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()

            return
        }

        let updatedContent = fileContent.replacingOccurrences(
            of: searchTerm,
            with: replacingTerm,
            options: replaceOptions,
            range: keywordRange
        )

        do {
            try updatedContent.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "An error occurred while writing to: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Replaces a single search result (the "Replace" action for one match). Updates the open document if the
    /// file is open, otherwise rewrites it on disk, then removes the match from the result list.
    @MainActor
    func replaceMatch(_ match: SearchResultMatchModel, replacingTerm: String) async {
        let url = match.file.url

        if let file = workspace.workspaceFileManager?.getFile(url.path)
                    ?? workspace.workspaceFileManager?.getFile(url.relativePath),
           let document = file.fileDocument,
           let storage = document.content {
            let nsString = storage.string as NSString
            guard let range = rangeForMatch(match, in: nsString) else { return }
            let updated = nsString.replacingCharacters(in: range, with: replacingTerm)
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: updated)
            document.updateChangeCount(.changeDone)
        } else {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            let nsString = content as NSString
            guard let range = rangeForMatch(match, in: nsString) else { return }
            let updated = nsString.replacingCharacters(in: range, with: replacingTerm)
            try? updated.write(to: url, atomically: true, encoding: .utf8)
        }

        removeSearchResultMatch(match)
    }

    /// Locates a match in the given content, verifying the stored offset and falling back to a search.
    private func rangeForMatch(_ match: SearchResultMatchModel, in content: NSString) -> NSRange? {
        let length = (match.matchedText as NSString).length
        guard length > 0 else { return nil }
        let offset = min(max(match.offset, 0), content.length)
        if offset + length <= content.length,
           content.substring(with: NSRange(location: offset, length: length)) == match.matchedText {
            return NSRange(location: offset, length: length)
        }
        let found = content.range(
            of: match.matchedText,
            options: [],
            range: NSRange(location: offset, length: content.length - offset)
        )
        return found.location == NSNotFound ? nil : found
    }

    @MainActor
    private func removeSearchResultMatch(_ match: SearchResultMatchModel) {
        guard let index = searchResult.firstIndex(where: { result in
            result.lineMatches.contains { $0.id == match.id }
        }) else {
            return
        }
        searchResult[index].lineMatches.removeAll { $0.id == match.id }
        if searchResult[index].lineMatches.isEmpty {
            searchResult.remove(at: index)
        }
        searchResultsCount = searchResult.reduce(0) { $0 + $1.lineMatches.count }
        searchResultsFileCount = searchResult.count
    }

    func setStatus(_ status: FindNavigatorStatus) async {
        await MainActor.run {
            self.findNavigatorStatus = status
        }
    }
}
