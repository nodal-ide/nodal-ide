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
    private(set) var localSiteCoordinator: WorkspaceLocalSiteCoordinator?

    // MARK: Created when the workspace is configured

    private(set) var workspaceSettingsManager: CEWorkspaceSettings?
    private(set) var searchState: WorkspaceSearchService?
    private(set) var openQuicklyViewModel: OpenQuicklyViewModel?
    private(set) var commandsPaletteState: QuickActionsViewModel?
    private(set) var sourceControlCoordinator: SourceControlCoordinator?
    private(set) var workspaceFileManager: CEWorkspaceFileManager?
    private(set) var taskManager: TaskManager?
    private(set) var runConfigurationStore: RunConfigurationStore?
    private(set) var runController: RunController?
    private(set) var testRunner: TestRunner?
    private(set) var breakpointStore: BreakpointStore?
    private(set) var debugController: DebugController?

    /// The catalog of built-in languages plus this workspace's enabled extension syntax packs.
    private(set) var languageCatalogStore: LanguageCatalogStore?

    var sourceControlManager: SourceControlManager? { sourceControlCoordinator?.primaryRepository }

    /// Constructs the workspace-dependent services. Called once a workspace URL is known.
    func configure(workspace: WorkspaceDocument, url: URL) {
        let settingsManager = CEWorkspaceSettings(workspaceURL: url)
        workspaceSettingsManager = settingsManager
        searchState = WorkspaceSearchService(workspace)
        openQuicklyViewModel = OpenQuicklyViewModel(fileURL: url)
        commandsPaletteState = QuickActionsViewModel()

        let coordinator = SourceControlCoordinator(
            workspaceURL: url,
            editorManager: editorManager,
            shellClient: currentWorld.shellClient
        )
        let workspaceFileManager = CEWorkspaceFileManager(
            folderUrl: url,
            ignoredFilesAndFolders: Self.ignoredFilesAndDirectory,
            sourceControlManager: nil
        )
        workspaceFileManager.sourceControlCoordinator = coordinator
        coordinator.fileManager = workspaceFileManager
        self.sourceControlCoordinator = coordinator
        self.workspaceFileManager = workspaceFileManager

        Task { await coordinator.setup() }

        taskManager = TaskManager(workspaceSettings: settingsManager.settings, workspaceURL: url)
        runConfigurationStore = RunConfigurationStore(workspaceURL: url)
        runController = RunController(workspace: workspace)
        testRunner = TestRunner(workspace: workspace)
        breakpointStore = BreakpointStore(workspaceURL: url)
        debugController = DebugController(workspace: workspace)

        // Read the workspace's extension syntax packs early so detection, highlighting and the
        // inspector all see contributed languages as soon as the workspace is configured.
        languageCatalogStore = LanguageCatalogStore(workspaceRoot: url)

        stateStore = WorkspaceStateStore(fileURL: url)
        taskNotificationHandler.workspaceURL = url
        self.workspaceFileManager?.addObserver(undoRegistration)
        editorManager.restoreFromState(workspace)
        utilityAreaModel.restoreFromState(workspace)

        startProjectRuntime(workspace: workspace, url: url, settings: settingsManager)
    }

    /// Starts the workspace's runtime: the resolved runtime environment, the local site, and the
    /// background project scan.
    ///
    /// Kept out of ``configure(workspace:url:)`` because everything here kicks off asynchronous work
    /// rather than constructing a service.
    private func startProjectRuntime(
        workspace: WorkspaceDocument,
        url: URL,
        settings: CEWorkspaceSettings
    ) {
        // Resolve the runtime environment now and keep it in sync with the project's runtime pins.
        runtimeCoordinator = WorkspaceRuntimeCoordinator(workspace: workspace)
        runtimeCoordinator?.start(settingsManager: settings)

        // Keep the project's local site in sync with its `site` + `runtimes` settings.
        let siteRunner = LocalSiteRunner(
            operations: AppServices.localProxy.makeOperations(
                workspaceURL: url,
                site: { [weak settings] in settings?.settings.site ?? LocalSiteSettings() },
                taskManager: taskManager
            )
        )
        let siteCoordinator = WorkspaceLocalSiteCoordinator(workspaceURL: url, runner: siteRunner)
        siteCoordinator.start(settingsManager: settings)
        localSiteCoordinator = siteCoordinator
        runController?.bindLocalSite(siteCoordinator, settingsManager: settings)

        let autoStart = AppServices.settings.preferences.localDomains.autoStartSitesOnOpen
        Task { await siteCoordinator.startIfEnabledOnOpen(autoStart: autoStart) }

        // Kick off a background project scan (symbols + code-quality diagnostics) shortly after launch
        // so the Problems panel isn't limited to open files. Only for PHP projects.
        launchCoordinator.scheduleProjectScan(
            at: url,
            language: settings.settings.project.language
        )
    }

    /// Releases the workspace-dependent services (keeping the eagerly-created ones).
    func tearDown() {
        runtimeCoordinator = nil
        if let siteCoordinator = localSiteCoordinator {
            Task { await siteCoordinator.shutdown() }
        }
        localSiteCoordinator = nil
        workspaceFileManager?.cleanUp()
        workspaceSettingsManager?.cleanUp()
        workspaceSettingsManager = nil
        searchState = nil
        openQuicklyViewModel = nil
        commandsPaletteState = nil
        sourceControlCoordinator = nil
        workspaceFileManager = nil
        taskManager = nil
        runConfigurationStore = nil
        runController = nil
        testRunner = nil
        breakpointStore = nil
        debugController = nil
        languageCatalogStore = nil
    }
}
