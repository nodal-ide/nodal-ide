//
//  GitClient+Push.swift
//  CodeEdit
//
//  Created by Albert Vinizhanau on 10/20/23.
//

import Foundation

extension GitClient {
    /// Push changes to remote.
    ///
    /// `--set-upstream` is only valid together with an explicit remote and branch, so the flags are assembled
    /// independently of the positional arguments instead of being dropped when either is missing.
    func pushToRemote(
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false,
        force: Bool = false,
        tags: Bool = false
    ) async throws {
        var arguments = ["push"]
        if force {
            arguments.append("--force")
        }
        if tags {
            arguments.append("--tags")
        }
        if let remote, let branch {
            if setUpstream {
                arguments.append("--set-upstream")
            }
            arguments.append(contentsOf: [remote, branch])
        } else if let remote {
            arguments.append(remote)
        }

        let output = try await self.run(arguments.joined(separator: " "))

        if output.contains("rejected") || output.contains("fatal:") {
            throw GitClientError.outputError(output)
        }
    }
}
