//
//  WorkspaceDocument+SearchExtraction.swift
//  CodeEdit
//
//  Line/range extraction helpers used by the project search results.
//

import Foundation

extension WorkspaceSearchService {
    /// Extracts the range of the search term within the line preceding a matching occurrence.
    ///
    /// - Parameters:
    ///   - preLine: The line preceding the matching occurrence within the file content.
    ///   - matchWordLength: The length of the search term.
    ///
    /// - Returns: A range representing the position of the search term within the `preLine`.
    ///
    /// This function calculates the range of the search term within
    /// the provided line preceding a matching occurrence.
    /// It considers the length of the search term to determine
    /// the lower and upper bounds of the keyword range within the line.
    nonisolated func extractKeywordRange(from preLine: String, matchWordLength: Int) -> Range<String.Index> {
        let keywordLowerBound = preLine.index(
            preLine.endIndex,
            offsetBy: -matchWordLength,
            limitedBy: preLine.startIndex
        ) ?? preLine.endIndex
        let keywordUpperBound = preLine.endIndex

        return keywordLowerBound..<keywordUpperBound
    }

    /// Extracts the line following a matching occurrence within a file.
    ///
    /// - Parameters:
    ///   - matchRange: The range of the matched substring within the entire file content.
    ///   - fileContent: The content of the file where the match was found.
    ///
    /// - Returns: A string representing the line following the match.
    ///
    /// This function retrieves the line following a matching occurrence within the provided file content.
    /// It considers a context of up to 60 characters after the match and clips the result to the first
    /// occurrence of a newline character, ensuring that only the relevant portion of the line is displayed.
    /// The extracted line is then converted to a string before being returned.
    nonisolated func extractPostLine(from matchRange: Range<String.Index>, fileContent: String) -> String {
        let postRangeStart = matchRange.upperBound
        let postRangeEnd = fileContent.index(
            matchRange.upperBound,
            offsetBy: 60,
            limitedBy: fileContent.endIndex
        ) ?? fileContent.endIndex

        let postRange = postRangeStart..<postRangeEnd
        let postLineWithNewLines = fileContent[postRange]

        let firstNewLineIndexInPostLine = postLineWithNewLines.firstIndex(of: "\n") ?? postLineWithNewLines.endIndex
        return String(postLineWithNewLines[..<firstNewLineIndexInPostLine])
    }

    /// Resets the search results along with counts for overall results and file-specific results.
    func clearResults() {
        searchResult.removeAll()
        searchResultsCount = 0
        searchResultsFileCount = 0
        findNavigatorStatus = .none
    }

    /// Evaluates a matched file to determine if it contains any search matches.
    /// Requires a file score from the search model.
    ///
    /// Evaluates the file's contents asynchronously.
    ///
    /// - Parameters:
    ///   - fileURL: The `URL` of the file to evaluate.
    ///   - fileScore:  The file's score from a ``SearchIndexer``
    ///   - regexPattern: The pattern to evaluate against the file's contents.
    /// - Returns: `nil` if there are no relevant search matches, or a search result if matches are found.
    nonisolated func evaluateSearchResult(
        fileURL: URL,
        fileScore: Float,
        regexPattern: String,
        caseSensitive: Bool
    ) async -> SearchResultModel? {
        var newResult = SearchResultModel(
            file: CEWorkspaceFile(url: fileURL),
            score: fileScore
        )

        await evaluateFile(query: regexPattern, searchResult: &newResult, caseSensitive: caseSensitive)

        return newResult.lineMatches.isEmpty ? nil : newResult
    }
}
