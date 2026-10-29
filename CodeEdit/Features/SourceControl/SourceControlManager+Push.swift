//
//  SourceControlManager+Push.swift
//  CodeEdit
//

import Foundation

extension SourceControlManager {
    /// Push changes to remote.
    ///
    /// The remote and branch are resolved here rather than trusted from the push sheet: the pickers can leave
    /// either unset (re-opened sheets, detached metadata), and a bare `git push` silently fails or pushes the
    /// wrong ref. Missing values fall back to the tracked upstream, then the current branch and first remote.
    func push(
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false,
        force: Bool = false,
        tags: Bool = false
    ) async throws {
        guard let currentBranch else {
            throw GitClient.GitClientError.outputError("No branch is checked out, nothing to push.")
        }

        let resolvedBranch = branch ?? currentBranch.name
        guard let resolvedRemote = remote ?? upstreamRemoteName(for: currentBranch) ?? remotes.first?.name else {
            throw GitClient.GitClientError.noRemoteConfigured
        }

        try await gitClient.pushToRemote(
            remote: resolvedRemote,
            branch: resolvedBranch,
            setUpstream: setUpstream || (branch == nil && currentBranch.upstream == nil),
            force: force,
            tags: tags
        )

        await refreshCurrentBranch()
        await refreshNumberOfUnsyncedCommits()
    }

    /// Extracts the remote name from a branch's upstream, e.g. `origin/main` -> `origin`.
    private func upstreamRemoteName(for branch: GitBranch) -> String? {
        guard let upstream = branch.upstream, let name = upstream.split(separator: "/").first else {
            return nil
        }
        return String(name)
    }
}
