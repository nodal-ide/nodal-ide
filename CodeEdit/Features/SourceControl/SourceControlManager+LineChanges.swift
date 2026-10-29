//
//  SourceControlManager+LineChanges.swift
//  CodeEdit
//

import Foundation
import CodeEditSourceEditor

extension SourceControlManager {
    /// Files above this size are skipped: one diff would cost more than the ribbon is worth.
    static let maximumLineChangeFileSize = 4 * 1024 * 1024

    /// Returns the uncommitted line changes for a file, relative to `HEAD`.
    ///
    /// - Parameter untracked: Whether the file is untracked. Resolved by the caller on the main actor so this method
    ///   never reads publisher-backed state off-main.
    func lineChanges(for url: URL, untracked: Bool) async -> [LineChange] {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
              size.intValue <= Self.maximumLineChangeFileSize else {
            return []
        }

        let diff: FileDiff?
        if untracked {
            diff = untrackedDiff(for: url)
        } else {
            let root = gitClient.directoryURL.standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { return [] }
            let relative = String(path.dropFirst(root.count + 1))
            diff = (try? await gitClient.diffAgainstHEAD(for: relative)).map(DiffParser.parse)
        }

        guard let diff else { return [] }
        return LineChangeMapper.changes(from: diff)
    }
}
