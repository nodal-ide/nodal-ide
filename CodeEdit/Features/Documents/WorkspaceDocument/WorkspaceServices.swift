//
//  WorkspaceServices.swift
//  CodeEdit
//
//  Composition root for workspace-scoped services. `WorkspaceDocument` owns one and exposes the
//  individual services through computed forwards, so call sites are unchanged.
//

import Foundation

/// Owns the workspace-scoped services that used to be stored (and wired) directly on
/// `WorkspaceDocument`.
///
/// Services that don't need the workspace URL are created eagerly; the rest are created in
/// ``configure(workspace:url:)`` once the workspace URL is known, and released in ``tearDown()``.
@MainActor
final class WorkspaceServices {
    /// Files/folders ignored by the workspace file manager.
    private static let ignoredFilesAndDirectory: Set<String> = [".DS_Store"]

    // MARK: Eagerly created

    let editorManager = EditorManager()
    let statusBarViewModel = StatusBarViewModel()
    let utilityAreaModel = UtilityAreaViewModel()
    let listenerModel = WorkspaceNotificationModel()
    let notificationPanel = NotificationPanelViewModel()
    let undoRegistration = UndoManagerRegistration()
    let taskNotificationHandler = TaskNotificationHandler()

    // MARK: Lifecycle helpers

    /// Persistence for per-workspace UI state.
    private(set) var stateStore = WorkspaceStateStore(fileURL: nil)
    private let launchCoordinator = WorkspaceLaunchCoordinator()
    private var runtimeCoordinator: WorkspaceRuntimeCoordinator?

    // MARK: Created when the workspace is configured

    private(set) var workspaceSettingsManager: CEWorkspaceSettings?
    private(set) var searchState: WorkspaceSearchService?
    private(set) var openQuicklyViewModel: OpenQuicklyViewModel?
    private(set) var commandsPaletteState: QuickActionsViewModel?
    private(set) var sourceControlManager: SourceControlManager?
    private(set) var workspaceFileManager: CEWorkspaceFileManager?
    private(set) var taskManager: TaskManager?
    private(set) var runConfigurationStore: RunConfigurationStore?
    private(set) var runController: RunController?
    private(set) var testRunner: TestRunner?
    private(set) var breakpointStore: BreakpointStore?
    private(set) var debugController: DebugController?

    /// Constructs the workspace-dependent services. Called once a workspace URL is known.
    func configure(workspace: WorkspaceDocument, url: URL) {
        let settingsManager = CEWorkspaceSettings(workspaceURL: url)
        workspaceSettingsManager = settingsManager
        searchState = WorkspaceSearchService(workspace)
        openQuicklyViewModel = OpenQuicklyViewModel(fileURL: url)
        commandsPaletteState = QuickActionsViewModel()

        let sourceControlManager = SourceControlManager(workspaceURL: url, editorManager: editorManager)
        let workspaceFileManager = CEWorkspaceFileManager(
            folderUrl: url,
            ignoredFilesAndFolders: Self.ignoredFilesAndDirectory,
            sourceControlManager: sourceControlManager
        )
        sourceControlManager.fileManager = workspaceFileManager
        self.sourceControlManager = sourceControlManager
        self.workspaceFileManager = workspaceFileManager

        taskManager = TaskManager(workspaceSettings: settingsManager.settings, workspaceURL: url)
        runConfigurationStore = RunConfigurationStore(workspaceURL: url)
        runController = RunController(workspace: workspace)
        testRunner = TestRunner(workspace: workspace)
        breakpointStore = BreakpointStore(workspaceURL: url)
        debugController = DebugController(workspace: workspace)

        stateStore = WorkspaceStateStore(fileURL: url)
        taskNotificationHandler.workspaceURL = url
        self.workspaceFileManager?.addObserver(undoRegistration)
        editorManager.restoreFromState(workspace)
        utilityAreaModel.restoreFromState(workspace)

        // Resolve the runtime environment now and keep it in sync with the project's runtime pins.
        runtimeCoordinator = WorkspaceRuntimeCoordinator(workspace: workspace)
        runtimeCoordinator?.start(settingsManager: settingsManager)

        // Kick off a background project scan (symbols + code-quality diagnostics) shortly after launch
        // so the Problems panel isn't limited to open files. Only for PHP projects.
        launchCoordinator.scheduleProjectScan(
            at: url,
            language: settingsManager.settings.project.language
        )
    }

    /// Releases the workspace-dependent services (keeping the eagerly-created ones).
    func tearDown() {
        runtimeCoordinator = nil
        workspaceFileManager?.cleanUp()
        workspaceSettingsManager?.cleanUp()
        workspaceSettingsManager = nil
        searchState = nil
        openQuicklyViewModel = nil
        commandsPaletteState = nil
        sourceControlManager = nil
        workspaceFileManager = nil
        taskManager = nil
        runConfigurationStore = nil
        runController = nil
        testRunner = nil
        breakpointStore = nil
        debugController = nil
    }
}
