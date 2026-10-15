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
    /// When `true`, the diff shows the staged (index) changes; otherwise the working tree.
    @Published var staged = false

    private weak var manager: SourceControlManager?

    private init() {}

    /// Loads (and shows) the diff for a changed file.
    func load(file: GitChangedFile, manager: SourceControlManager) {
        self.file = file
        self.manager = manager
        self.staged = false
        self.diff = nil
        self.errorMessage = nil
        self.isLoading = true

        Task {
            var result = await manager.fileDiff(for: file, staged: false)
            // Nothing in the working tree but the file has staged changes — show the staged diff.
            if result?.hunks.isEmpty ?? true, file.isStaged {
                self.staged = true
                result = await manager.fileDiff(for: file, staged: true)
            }
            self.diff = result
            if result == nil {
                self.errorMessage = "Could not load the diff for this file."
            }
            self.isLoading = false
        }
    }

    /// Switches between working-tree and staged views.
    func setStaged(_ newValue: Bool) {
        guard staged != newValue else { return }
        staged = newValue
        reload()
    }

    func reload() {
        guard let file, let manager else { return }
        isLoading = true
        errorMessage = nil
        let staged = self.staged
        Task {
            let result = await manager.fileDiff(for: file, staged: staged)
            self.diff = result
            if result == nil {
                self.errorMessage = "Could not load the diff for this file."
            }
            self.isLoading = false
        }
    }

    /// Stages a single hunk (or the whole file when it's untracked).
    func stageHunk(_ hunk: DiffHunk) {
        guard let file, let manager, let diff else { return }
        if file.anyStatus() == .untracked || diff.header.isEmpty {
            Task {
                try? await manager.add([file.fileURL])
                reload()
            }
            return
        }
        let patch = diff.patch(for: hunk)
        Task {
            try? await manager.stagePatch(patch)
            reload()
        }
    }

    /// Unstages a single hunk.
    func unstageHunk(_ hunk: DiffHunk) {
        guard let manager, let diff else { return }
        let patch = diff.patch(for: hunk)
        Task {
            try? await manager.unstagePatch(patch)
            reload()
        }
    }
}
