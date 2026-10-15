//
//  DebugController.swift
//  CodeEdit
//
//  Owns the debug session for a workspace and keeps breakpoints in sync.
//

import Combine
import Foundation

@MainActor
final class DebugController: ObservableObject {
    let session = DebugSession()

    private weak var workspace: WorkspaceDocument?
    private var cancellables = Set<AnyCancellable>()

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
        workspace.breakpointStore?.$breakpoints
            .sink { [weak self] _ in self?.syncBreakpoints() }
            .store(in: &cancellables)
        workspace.statusBarViewModel?.$isBreakpointEnabled
            .sink { [weak self] _ in self?.syncBreakpoints() }
            .store(in: &cancellables)
        syncBreakpoints()
    }

    func start(_ options: DebugSession.LaunchOptions) {
        session.start(options)
    }

    func stop() {
        session.stop()
    }

    /// Pushes the workspace's (enabled) breakpoints to the session, honoring the master toggle.
    private func syncBreakpoints() {
        let enabled = workspace?.statusBarViewModel?.isBreakpointEnabled ?? true
        let breakpoints = enabled ? (workspace?.breakpointStore?.breakpoints ?? []) : []
        session.updateBreakpoints(breakpoints)
    }
}
