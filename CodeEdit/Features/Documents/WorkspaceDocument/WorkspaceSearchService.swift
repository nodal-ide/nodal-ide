//
//  WorkspaceSearchService.swift
//  CodeEdit
//
//  Created by Tom Ludwig on 16.01.24.
//

import Foundation

/// Workspace-wide find-and-replace state and operations: the search index, the current results, and
/// the find-navigator status.
///
/// Formerly `WorkspaceDocument.SearchState`; promoted to a top-level service so it no longer lives in
/// the document's namespace. Behavior is unchanged. Its operations are spread across
/// `WorkspaceDocument+Index`, `WorkspaceDocument+Find`, `WorkspaceDocument+FindAndReplace` and
/// `WorkspaceDocument+SearchExtraction` extensions.
final class WorkspaceSearchService: ObservableObject {
    enum IndexStatus: Equatable {
        case none
        case indexing(progress: Double)
        case done
    }

    enum FindNavigatorStatus: Equatable {
        case none
        case searching
        case replacing
        case found
        case replaced(updatedFiles: Int)
        case failed(errorMessage: String)
    }

    @Published var searchResult: [SearchResultModel] = []
    @Published var searchResultsFileCount: Int = 0
    @Published var searchResultsCount: Int = 0
    /// Stores the user's input, shown when no files are found, and persists across navigation items.
    @Published var searchQuery: String = ""
    @Published var replaceText: String = ""

    @Published var indexStatus: IndexStatus = .none

    @Published var findNavigatorStatus: FindNavigatorStatus = .none

    @Published var shouldFocusSearchField: Bool = false

    unowned var workspace: WorkspaceDocument
    var tempSearchResults = [SearchResultModel]()
    var caseSensitive: Bool = false
    var indexer: SearchIndexer?
    var selectedMode: [SearchModeModel] = [
        .Find,
        .Text,
        .Containing
    ]

    init(_ workspace: WorkspaceDocument) {
        self.workspace = workspace
        self.indexer = SearchIndexer.Memory.create()
        addProjectToIndex()
    }

    /// Represents the compare options to be used for find and replace.
    ///
    /// Computed (not cached) so it always reflects the current search mode and case sensitivity.
    var replaceOptions: NSString.CompareOptions {
        var options: NSString.CompareOptions = []

        if selectedMode.second == .RegularExpression {
            options.insert(.regularExpression)
        }

        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        return options
    }
}
