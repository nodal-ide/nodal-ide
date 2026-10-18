//
//  WorkspaceServices.swift
//  CodeEdit
//
//  Composition root for workspace-scoped services. `WorkspaceDocument` creates one of these and
//  exposes the individual services through computed forwards, so call sites are unchanged.
//

import Foundation

/// Owns the workspace-scoped services that used to be stored (and wired) directly on
/// `WorkspaceDocument`. Grows group by group as services are moved off the document.
@MainActor
final class WorkspaceServices {
    // MARK: Run / debug / tasks

    let taskManager: TaskManager?
    let runConfigurationStore: RunConfigurationStore?
    let runController: RunController?
    let testRunner: TestRunner?
    let breakpointStore: BreakpointStore?
    let debugController: DebugController?

    init(workspace: WorkspaceDocument, url: URL, settingsManager: CEWorkspaceSettings?) {
        if let settingsManager {
            taskManager = TaskManager(workspaceSettings: settingsManager.settings, workspaceURL: url)
        } else {
            taskManager = nil
        }
        runConfigurationStore = RunConfigurationStore(workspaceURL: url)
        runController = RunController(workspace: workspace)
        testRunner = TestRunner(workspace: workspace)
        breakpointStore = BreakpointStore(workspaceURL: url)
        debugController = DebugController(workspace: workspace)
    }
}
