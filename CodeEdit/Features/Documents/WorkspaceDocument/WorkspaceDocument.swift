//
//  WorkspaceDocument.swift
//  CodeEdit
//
//  Created by Pavel Kasila on 17.03.22.
//

import AppKit
import SwiftUI
import Combine
import Foundation
import LanguageServerProtocol

@objc(WorkspaceDocument)
final class WorkspaceDocument: NSDocument, ObservableObject, NSToolbarDelegate {
    @Published var sortFoldersOnTop: Bool = true
    /// A string used to filter the displayed files and folders in the project navigator area based on user input.
    @Published var navigatorFilter: String = ""
    /// Whether the workspace only shows files with changes.
    @Published var sourceControlFilter = false
    /// Whether the workspace only shows files modified recently.
    @Published var recentsFilter = false

    /// Persistence for per-workspace UI state; always resolves against the current `fileURL`.
    private var stateStore: WorkspaceStateStore {
        WorkspaceStateStore(fileURL: fileURL)
    }

    var workspaceFileManager: CEWorkspaceFileManager?

    var editorManager: EditorManager? = EditorManager()
    var statusBarViewModel: StatusBarViewModel? = StatusBarViewModel()
    var utilityAreaModel: UtilityAreaViewModel? = UtilityAreaViewModel()
    var searchState: SearchState?
    var openQuicklyViewModel: OpenQuicklyViewModel?
    var commandsPaletteState: QuickActionsViewModel?
    var listenerModel: WorkspaceNotificationModel = .init()
    var sourceControlManager: SourceControlManager?

    var taskManager: TaskManager?
    var runConfigurationStore: RunConfigurationStore?
    var runController: RunController?
    var testRunner: TestRunner?
    var breakpointStore: BreakpointStore?
    var debugController: DebugController?
    var workspaceSettingsManager: CEWorkspaceSettings?
    var taskNotificationHandler: TaskNotificationHandler = TaskNotificationHandler()

    private var runtimeCoordinator: WorkspaceRuntimeCoordinator?

    var undoRegistration: UndoManagerRegistration = UndoManagerRegistration()

    var notificationPanel = NotificationPanelViewModel()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        notificationPanel.workspace = self

        // Observe changes to notification panel
        notificationPanel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        NotificationCenter.default.removeObserver(self)
    }

    func getFromWorkspaceState(_ key: WorkspaceStateKey) -> Any? {
        return stateStore.value(for: key)
    }

    func addToWorkspaceState(key: WorkspaceStateKey, value: Any?) {
        stateStore.set(value, for: key)
    }

    // MARK: NSDocument

    private let ignoredFilesAndDirectory = [
        ".DS_Store"
    ]

    override static var autosavesInPlace: Bool {
        false
    }

    override var isDocumentEdited: Bool {
        false
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Note For anyone hoping to switch back to a Root-SwiftUI window:
        // See Commit 0200c87 for more details and to see what was previously here.
        // -----
        // Setting the "min size" like this is hacky, but SwiftUI overrides the contentRect and
        // any of the built-in window size functions & autosave stuff. So we have to set it like this.
        // SwiftUI also ignores this value, so it just manages to set the initial window size. *Hopefully* this
        // is fixed in the future.
        // ----
        let windowController = CodeEditWindowController(
            window: window,
            workspace: self
        )

        if let rectString = getFromWorkspaceState(.workspaceWindowSize) as? String {
            window.setFrame(NSRectFromString(rectString), display: true, animate: false)
        } else {
            window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 900), display: true, animate: false)
            window.center()
        }

        window.setAccessibilityIdentifier("workspace")
        window.setAccessibilityDocument(self.fileURL?.absoluteString)

        self.addWindowController(windowController)

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Set Up Workspace

    private func initWorkspaceState(_ url: URL) throws {
        // Ensure the URL ends with a "/" to prevent certain URL(filePath:relativeTo) initializers from
        // placing the file one directory above our workspace. This quick fix appends a "/" if needed.
        var url = url
        if !url.absoluteString.hasSuffix("/") {
            url = URL(filePath: url.absoluteURL.path(percentEncoded: false) + "/")
        }

        self.fileURL = url
        self.displayName = url.lastPathComponent

        let sourceControlManager = SourceControlManager(
            workspaceURL: url,
            editorManager: editorManager!
        )

        self.workspaceFileManager = .init(
            folderUrl: url,
            ignoredFilesAndFolders: Set(ignoredFilesAndDirectory),
            sourceControlManager: sourceControlManager
        )
        self.sourceControlManager = sourceControlManager
        sourceControlManager.fileManager = workspaceFileManager
        self.searchState = .init(self)
        self.openQuicklyViewModel = .init(fileURL: url)
        self.commandsPaletteState = .init()
        self.workspaceSettingsManager = CEWorkspaceSettings(workspaceURL: url)
        if let workspaceSettingsManager {
            self.taskManager = TaskManager(
                workspaceSettings: workspaceSettingsManager.settings,
                workspaceURL: url
            )
        }
        self.runConfigurationStore = RunConfigurationStore(workspaceURL: url)
        self.runController = RunController(workspace: self)
        self.testRunner = TestRunner(workspace: self)
        self.breakpointStore = BreakpointStore(workspaceURL: url)
        self.debugController = DebugController(workspace: self)
        self.taskNotificationHandler.workspaceURL = url

        workspaceFileManager?.addObserver(undoRegistration)
        editorManager?.restoreFromState(self)
        utilityAreaModel?.restoreFromState(self)

        // Resolve the runtime environment now and keep it in sync with the project's runtime pins.
        self.runtimeCoordinator = WorkspaceRuntimeCoordinator(workspace: self)
        runtimeCoordinator?.start(settingsManager: workspaceSettingsManager)

        // Kick off a background project scan (symbols + code-quality diagnostics) shortly after launch
        // so the Problems panel isn't limited to open files. Only for PHP projects.
        let projectLanguage = workspaceSettingsManager?.settings.project.language.lowercased() ?? ""
        if projectLanguage.isEmpty || projectLanguage == "php" {
            startProjectScan(at: url)
        }
    }

    /// Starts a background PHP project scan (symbols + diagnostics) a moment after launch.
    private func startProjectScan(at root: URL) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            _ = PHPWorkspaceIndex.shared.index(for: root)
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        try initWorkspaceState(url)
    }

    override func write(to url: URL, ofType typeName: String) throws {}

    // MARK: Close Workspace

    override func close() {
        // Drop this workspace's diagnostics so they don't leak into other workspaces.
        if let root = workspaceFileManager?.folderUrl ?? fileURL {
            DiagnosticsStore.shared.clear(under: root)
        }
        super.close()
        editorManager?.saveRestorationState(self)
        utilityAreaModel?.saveRestorationState(self)

        cancellables.forEach({ $0.cancel() })
        runtimeCoordinator = nil
        statusBarViewModel = nil
        utilityAreaModel = nil
        searchState = nil
        editorManager = nil
        openQuicklyViewModel = nil
        commandsPaletteState = nil
        sourceControlManager = nil
        workspaceFileManager?.cleanUp()
        workspaceFileManager = nil
        workspaceSettingsManager?.cleanUp()
        workspaceSettingsManager = nil
        taskManager = nil
    }

    /// Determines the windows should be closed.
    ///
    /// This method iterates all edited documents If there are any edited documents.
    ///
    /// A panel giving the user the choice of canceling, discarding changes, or saving is presented while iteration.
    ///
    /// If the user chooses cancel on the panel, iteration is broken.
    ///
    /// In the last step, `shouldCloseSelector` is called with true if all documents are clean, otherwise false
    ///
    /// - Parameters:
    ///   - windowController: The windowController may be closed.
    ///   - delegate: The object which is a target of `shouldCloseSelector`.
    ///   - shouldClose: The callback which receives result of this method.
    ///   - contextInfo: The additional info which is not used in this method.
    override func shouldCloseWindowController(
        _ windowController: NSWindowController,
        delegate: Any?,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let object = (delegate as? NSObject),
              let shouldCloseSelector = shouldCloseSelector,
              let contextInfo = contextInfo
        else {
            super.shouldCloseWindowController(
                windowController,
                delegate: delegate,
                shouldClose: shouldCloseSelector,
                contextInfo: contextInfo
            )
            return
        }
        // Save unsaved changes before closing
        let editedCodeFiles = editorManager?.editorLayout
            .gatherOpenFiles()
            .compactMap(\.fileDocument)
            .filter(\.isDocumentEdited) ?? []

        for editedCodeFile in editedCodeFiles where !DocumentCloseConfirmation.confirmClose(of: editedCodeFile) {
            // The user chose to cancel: stop and report that the window should not close.
            break
        }
        // Invoke shouldCloseSelector at delegate
        let implementation = object.method(for: shouldCloseSelector)
        let function = unsafeBitCast(
            implementation,
            to: (@convention(c)(Any, Selector, Any, Bool, UnsafeMutableRawPointer?) -> Void).self
        )
        let areAllOpenedCodeFilesClean = editorManager?.editorLayout.gatherOpenFiles()
            .compactMap(\.fileDocument)
            .allSatisfy { !$0.isDocumentEdited } ?? false
        function(object, shouldCloseSelector, self, areAllOpenedCodeFilesClean, contextInfo)
    }
}
