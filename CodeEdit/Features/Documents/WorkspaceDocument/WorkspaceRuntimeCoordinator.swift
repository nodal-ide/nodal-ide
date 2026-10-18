//
//  WorkspaceRuntimeCoordinator.swift
//  CodeEdit
//
//  Keeps a workspace's resolved runtime environment in sync with the project's runtime pins.
//  Extracted from `WorkspaceDocument` so the document no longer owns the Combine plumbing.
//

import Combine
import Foundation

/// Resolves the workspace's runtime environment once on startup, then re-resolves it whenever the
/// project's runtime pins change. Owned by `WorkspaceDocument`; released (and its subscriptions
/// cancelled) when the workspace closes.
@MainActor
final class WorkspaceRuntimeCoordinator {
    private weak var workspace: WorkspaceDocument?
    private var cancellables = Set<AnyCancellable>()

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    /// Performs the initial runtime resolution and, when a settings manager is available, observes
    /// the project's runtime pins to re-resolve on change.
    func start(settingsManager: CEWorkspaceSettings?) {
        guard let workspace else { return }
        Task { await RuntimeEnvironment.shared.refresh(workspace: workspace) }

        guard let settingsManager else { return }
        settingsManager.$settings
            .map(\.runtimes)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let workspace = self.workspace else { return }
                Task { await RuntimeEnvironment.shared.refresh(workspace: workspace) }
            }
            .store(in: &cancellables)
    }
}
