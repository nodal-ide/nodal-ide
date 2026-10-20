//
//  SourceControlManager+Submodules.swift
//  CodeEdit
//

import Foundation

extension SourceControlManager {
    /// Updates an initialized submodule to the commit recorded by its parent repository.
    ///
    /// Runs from the parent repository so `git submodule update` operates on the
    /// submodule entry rather than the submodule's own nested submodules.
    func updateSubmodule() async throws {
        guard let parentRepoURL,
              !parentRepoURL.standardizedFileURL.componentCompare(workspaceURL.standardizedFileURL) else {
            return
        }

        let parentComponents = parentRepoURL.standardizedFileURL.pathComponents
        let relativePath = workspaceURL.standardizedFileURL.pathComponents
            .dropFirst(parentComponents.count)
            .joined(separator: "/")
        guard !relativePath.isEmpty else { return }

        let parentClient = GitClient(directoryURL: parentRepoURL, shellClient: currentWorld.shellClient)
        try await parentClient.submoduleUpdate(path: relativePath, initialize: true, recursive: true)
        await refreshAllChangedFiles()
    }
}
