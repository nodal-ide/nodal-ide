//
//  SourceControlManager+ChangesMetadata.swift
//  CodeEdit
//

import Foundation

extension SourceControlManager {
    /// Refreshes the metadata required by the Changes navigator for this repository.
    ///
    /// The repository and history navigators load the full branch and stash metadata on demand.
    func refreshChangesMetadata() async {
        await refreshCurrentBranch()
        try? await refreshRemotes(includeRemoteBranches: false)
        await refreshNumberOfUnsyncedCommits()
    }
}
