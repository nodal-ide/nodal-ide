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
    /// Files/folders ignored by the workspace file manager.
    private static let ignoredFilesAndDirectory: Set<String> = [".DS_Store"]

    // MARK: Editor / documents

    let editorManager = EditorManager()
    let statusBarViewModel = StatusBarViewModel()
    let utilityAreaModel = UtilityAreaViewModel()
    let sourceControlManager: SourceControlManager?
    let workspaceFileManager: CEWorkspaceFileManager?

    // MARK: Run / debug / tasks

    let taskManager: TaskManager?
    let runConfigurationStore: RunConfigurationStore?
    let runController: RunController?
    let testRunner: TestRunner?
    let breakpointStore: BreakpointStore?
    let debugController: DebugController?

    init(workspace: WorkspaceDocument, url: URL, settingsManager: CEWorkspaceSettings?) {
        let sourceControlManager = SourceControlManager(workspaceURL: url, editorManager: editorManager)
        let workspaceFileManager = CEWorkspaceFileManager(
            folderUrl: url,
            ignoredFilesAndFolders: Self.ignoredFilesAndDirectory,
            sourceControlManager: sourceControlManager
        )
        sourceControlManager.fileManager = workspaceFileManager
        self.sourceControlManager = sourceControlManager
        self.workspaceFileManager = workspaceFileManager

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
