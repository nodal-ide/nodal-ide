//
//  DiffViewerState.swift
//  CodeEdit
//
//  Shared state for the diff viewer window.
//

import Combine
import Foundation

@MainActor
final class DiffViewerState: ObservableObject {
    static let shared = DiffViewerState()

    @Published var file: GitChangedFile?
    @Published var diff: FileDiff?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    /// Loads (and shows) the diff for a changed file.
    func load(file: GitChangedFile, manager: SourceControlManager) {
        self.file = file
        self.diff = nil
        self.errorMessage = nil
        self.isLoading = true

        Task {
            var result = await manager.fileDiff(for: file, staged: false)
            // If there are no working-tree changes but the file is staged, show the staged diff.
            if result?.hunks.isEmpty ?? true, file.isStaged {
                result = await manager.fileDiff(for: file, staged: true)
            }
            self.diff = result
            if result == nil {
                self.errorMessage = "Could not load the diff for this file."
            }
            self.isLoading = false
        }
    }
}
