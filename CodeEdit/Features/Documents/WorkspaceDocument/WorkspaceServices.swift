//
//  WorkspaceServices.swift
//  CodeEdit
//
//  Composition root for workspace-scoped services. `WorkspaceDocument` owns one and exposes the
//  individual services through computed forwards, so call sites are unchanged.
//

import Combine
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
    let assistantSession = AssistantSession()
    let referencesSession = ReferencesSession()

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
    private var assistantSettingsCancellable: AnyCancellable?
    private var lastRetrievalSetting: Bool?
    private var lastHistorySetting: Bool?
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
        referencesSession.configure(workspace: workspace)
        assistantSession.configureContextProvider(WorkspaceAssistantContextProvider(workspace: workspace))
        let retrieveExcerpts = AppServices.settings.preferences.assistant.retrieveWorkspaceExcerpts
        lastRetrievalSetting = retrieveExcerpts
        assistantSession.setRetrievalEnabled(retrieveExcerpts)
        assistantSession.configureRetrieval(AssistantWorkspaceRetrievalService(rootURL: url))
        let saveHistory = AppServices.settings.preferences.assistant.saveHistory
        lastHistorySetting = saveHistory
        assistantSession.configureConversationHistory(
            store: AssistantConversationStore(workspaceURL: url),
            enabled: saveHistory
        )
        configureAssistantDefaults()
        assistantSession.citationOpener = { [weak workspace] citation in
            guard let workspace else { return false }
            return Self.openCitation(citation, in: workspace)
        }
        assistantSession.refreshProviderConfiguration()
        assistantSettingsCancellable = AppServices.settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let enabled = AppServices.settings.preferences.assistant.retrieveWorkspaceExcerpts
                    if self.lastRetrievalSetting != enabled {
                        self.lastRetrievalSetting = enabled
                        self.assistantSession.setRetrievalEnabled(enabled)
                    }
                    let saveHistory = AppServices.settings.preferences.assistant.saveHistory
                    if self.lastHistorySetting != saveHistory {
                        self.lastHistorySetting = saveHistory
                        self.assistantSession.setHistoryEnabled(saveHistory)
                    }
                    self.configureAssistantDefaults()
                    self.assistantSession.refreshProviderConfiguration()
                }
            }

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
        assistantSettingsCancellable = nil
        lastRetrievalSetting = nil
        lastHistorySetting = nil
        assistantSession.prepareForWorkspaceClose()
        assistantSession.stopRetrieval()
        assistantSession.citationOpener = nil
        referencesSession.clear()
    }

    private func configureAssistantDefaults() {
        let assistant = AppServices.settings.preferences.assistant
        assistantSession.configureDefaultContext(
            includeDiagnostics: assistant.includeDiagnosticsByDefault,
            includeTasks: assistant.includeTasksByDefault
        )
    }

    private static func openCitation(_ citation: AssistantCitation, in workspace: WorkspaceDocument) -> Bool {
        if let sourceID = citation.knowledgeSourceID {
            KnowledgeRouter.shared.requestOpen(sourceID: sourceID, path: citation.relativePath)
            return true
        }
        guard let root = workspace.workspaceFileManager?.folderUrl ?? workspace.fileURL,
              let url = AssistantPathUtilities.url(forRelativePath: citation.relativePath, root: root),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return false }
        workspace.editorManager?.revealSourceLocation(
            url: url,
            line: citation.line ?? 1,
            column: 1
        )
        return true
    }
}
