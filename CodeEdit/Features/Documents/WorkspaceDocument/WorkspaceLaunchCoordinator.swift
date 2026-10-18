//
//  WorkspaceLaunchCoordinator.swift
//  CodeEdit
//
//  Runs the deferred work that happens shortly after a workspace opens.
//

import Foundation

/// Runs the side-effects that happen shortly after a workspace opens.
///
/// Today that's a background PHP project scan (symbols + code-quality diagnostics) so the Problems
/// panel isn't limited to open files. Extracted from `WorkspaceDocument` so launch side-effects don't
/// live in the document.
@MainActor
struct WorkspaceLaunchCoordinator {
    /// Schedules the background project scan shortly after launch. No-op for non-PHP workspaces.
    func scheduleProjectScan(at root: URL, language: String) {
        let language = language.lowercased()
        guard language.isEmpty || language == "php" else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            _ = PHPWorkspaceIndex.shared.index(for: root)
        }
    }
}
