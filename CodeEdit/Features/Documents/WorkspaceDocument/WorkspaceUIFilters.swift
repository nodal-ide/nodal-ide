//
//  WorkspaceUIFilters.swift
//  CodeEdit
//
//  Navigator-area filter and sort state for a workspace, extracted from `WorkspaceDocument`.
//

import Combine

/// Holds the project-navigator filter/sort state: the name filter and the "recent files" / "source
/// control changes" quick filters. Kept as its own observable model so `WorkspaceDocument` doesn't
/// own view state; the document forwards `objectWillChange` and exposes computed accessors so
/// existing call sites keep working.
final class WorkspaceUIFilters: ObservableObject {
    /// Whether folders are sorted above files (vs. alphabetically).
    @Published var sortFoldersOnTop: Bool = true
    /// Text used to filter the displayed files and folders in the project navigator.
    @Published var navigatorFilter: String = ""
    /// Whether to only show files with changes.
    @Published var sourceControlFilter = false
    /// Whether to only show files modified recently.
    @Published var recentsFilter = false
}
