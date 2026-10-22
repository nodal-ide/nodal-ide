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
    /// Project-navigator filter/sort state (formerly four `@Published` properties on this class).
    let filters = WorkspaceUIFilters()

    var sortFoldersOnTop: Bool {
        get { filters.sortFoldersOnTop }
        set { filters.sortFoldersOnTop = newValue }
    }

    var navigatorFilter: String {
        get { filters.navigatorFilter }
        set { filters.navigatorFilter = newValue }
    }

    var sourceControlFilter: Bool {
        get { filters.sourceControlFilter }
        set { filters.sourceControlFilter = newValue }
    }

    var recentsFilter: Bool {
        get { filters.recentsFilter }
        set { filters.recentsFilter = newValue }
    }

    /// Composition root for workspace-scoped services (see ``WorkspaceServices``). The services are
    /// exposed below through computed forwards so call sites are unchanged.
    let services = WorkspaceServices()

    // Eagerly-created services.
    var editorManager: EditorManager? { services.editorManager }
    var statusBarViewModel: StatusBarViewModel? { services.statusBarViewModel }
    var utilityAreaModel: UtilityAreaViewModel? { services.utilityAreaModel }
    var listenerModel: WorkspaceNotificationModel { services.listenerModel }
    var notificationPanel: NotificationPanelViewModel { services.notificationPanel }
    var undoRegistration: UndoManagerRegistration { services.undoRegistration }
    var taskNotificationHandler: TaskNotificationHandler { services.taskNotificationHandler }

    // Workspace-dependent services (created once the URL is known).
    var workspaceFileManager: CEWorkspaceFileManager? { services.workspaceFileManager }
    var sourceControlManager: SourceControlManager? { services.sourceControlManager }
    var sourceControlCoordinator: SourceControlCoordinator? { services.sourceControlCoordinator }
    var workspaceSettingsManager: CEWorkspaceSettings? { services.workspaceSettingsManager }
    var searchState: WorkspaceSearchService? { services.searchState }
    var openQuicklyViewModel: OpenQuicklyViewModel? { services.openQuicklyViewModel }
    var commandsPaletteState: QuickActionsViewModel? { services.commandsPaletteState }
    var taskManager: TaskManager? { services.taskManager }
    var runConfigurationStore: RunConfigurationStore? { services.runConfigurationStore }
    var runController: RunController? { services.runController }
    var testRunner: TestRunner? { services.testRunner }
    var breakpointStore: BreakpointStore? { services.breakpointStore }
    var debugController: DebugController? { services.debugController }
    var languageCatalogStore: LanguageCatalogStore? { services.languageCatalogStore }
    var localSiteCoordinator: WorkspaceLocalSiteCoordinator? { services.localSiteCoordinator }

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

        // Re-publish navigator filter changes so views observing the document stay in sync.
        filters.objectWillChange
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
        return services.stateStore.value(for: key)
    }

    func addToWorkspaceState(key: WorkspaceStateKey, value: Any?) {
        services.stateStore.set(value, for: key)
    }

    // MARK: NSDocument

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

        services.configure(workspace: self, url: url)
        observeSourceControlCoordinator()
    }

    /// `WorkspaceView` reads the coordinator's primary repository through a computed property, so
    /// re-publish coordinator changes as document changes. Without this the editor stays empty until
    /// an unrelated update happens after asynchronous repository discovery.
    private func observeSourceControlCoordinator() {
        guard let coordinator = sourceControlCoordinator else { return }
        coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    override func read(from url: URL, ofType typeName: String) throws {
        try initWorkspaceState(url)
    }

    override func write(to url: URL, ofType typeName: String) throws {}

    // MARK: Close Workspace

    override func close() {
        // Drop this workspace's diagnostics so they don't leak into other workspaces.
        if let root = workspaceFileManager?.folderUrl ?? fileURL {
            AppServices.diagnosticsStore.clear(under: root)
        }
        super.close()
        editorManager?.saveRestorationState(self)
        utilityAreaModel?.saveRestorationState(self)

        cancellables.forEach({ $0.cancel() })
        services.tearDown()
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
