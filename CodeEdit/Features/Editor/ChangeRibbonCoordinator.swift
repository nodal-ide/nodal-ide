//
//  ChangeRibbonCoordinator.swift
//  CodeEdit
//

import Combine
import CodeEditSourceEditor
import Foundation

/// Feeds uncommitted line changes into one editor's gutter ribbon.
///
/// Refreshes are generation-guarded: a request that finishes after a newer one was started is dropped instead of
/// overwriting newer results. Git work happens in ``ChangeRibbonService`` off the main actor; this type only publishes
/// the result to the controller.
@MainActor
final class ChangeRibbonCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private weak var codeFile: CodeFileDocument?
    private weak var workspace: WorkspaceDocument?
    private var service: ChangeRibbonService?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var changes: [LineChange] = []

    /// Mirrors the `showChangeRibbon` setting. Disabling clears the ribbon and stops diffing entirely.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                refresh()
            } else {
                refreshTask?.cancel()
                generation &+= 1
                apply([])
            }
        }
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        controller.lineChanges = changes
        refresh()
    }

    func controllerDidAppear(controller: TextViewController) {
        refresh()
    }

    func destroy() {
        refreshTask?.cancel()
        refreshTask = nil
        cancellables.removeAll()
        service = nil
        controller = nil
        codeFile = nil
        workspace = nil
    }

    func start(codeFile: CodeFileDocument, workspace: WorkspaceDocument?) {
        guard service == nil else { return }
        self.codeFile = codeFile
        self.workspace = workspace
        guard codeFile.fileURL != nil else { return }

        service = ChangeRibbonService(coordinatorProvider: { [weak workspace] in
            workspace?.sourceControlCoordinator
        })

        // A save clears the document's edited flag, which is exactly when the on-disk diff changes.
        codeFile.isDocumentEditedPublisher
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        // Status refreshes cover commits, staging, resets and branch switches. Debounced so a burst of file system
        // events starts a single diff.
        workspace?.sourceControlCoordinator?.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    /// Reloads the ribbon. Cheap when the file's signature is unchanged: the service answers from its cache.
    func refresh() {
        guard isEnabled, let url = codeFile?.fileURL, let service else { return }

        generation &+= 1
        let generation = generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let changes = await service.changes(for: url)
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            self.apply(changes)
        }
    }

    private func apply(_ changes: [LineChange]) {
        self.changes = changes
        controller?.lineChanges = changes
    }
}
