//
//  CEWorkspaceFileManager+DirectoryEvents.swift
//  CodeEdit
//
//  Created by Axel Martinez on 5/8/24.
//

import Foundation

/// This extension handles the file system events triggered by changes in the root folder.
extension CEWorkspaceFileManager {
    /// Called by `fsEventStream` when an event occurs.
    ///
    /// This method may be called on a background thread, but all work done by this function will be queued on the main
    /// thread.
    /// - Parameter events: An array of events that occurred.
    func fileSystemEventReceived(events: [DirectoryEventStream.Event]) {
        DispatchQueue.main.async {
            var files: Set<CEWorkspaceFile> = []
            for event in events {
                // Event returns file/folder that was changed, but in tree we need to update it's parent
                guard let parentUrl = URL(string: event.path, relativeTo: self.folderUrl)?.deletingLastPathComponent(),
                      let parentFileItem = self.flattenedFileItems[parentUrl.path] else {
                    continue
                }

                switch event.eventType {
                case .changeInDirectory, .itemChangedOwner, .itemModified:
                    // Can be ignored for now, these I think not related to tree changes
                    continue
                case .rootChanged:
                    // TODO: #1880 - Handle workspace root changing.
                    continue
                case .itemCreated, .itemCloned, .itemRemoved, .itemRenamed:
                    do {
                        try self.rebuildFiles(fromItem: parentFileItem)
                    } catch {
                        // swiftlint:disable:next line_length
                        self.logger.error("Failed to rebuild files for event: \(event.eventType.rawValue), path: \(event.path, privacy: .sensitive)")
                    }
                    files.insert(parentFileItem)
                }
            }
            if !files.isEmpty {
                self.notifyObservers(updatedItems: files)
            }

            if AppServices.settings.preferences.sourceControl.general.sourceControlIsEnabled &&
                AppServices.settings.preferences.sourceControl.general.refreshStatusLocally {
                self.handleGitEvents(events: events)
            }
        }
    }

    func handleGitEvents(events: [DirectoryEventStream.Event]) {
        let notGitChanges = events.filter({ !$0.path.contains(".git/") })

        let gitFolderChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git"
        })

        let gitIndexChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git/index"
        })

        let gitStashChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git/refs/stash"
        })

        let gitBranchChange = events.first(where: {
            $0.path.contains("\(self.folderUrl.relativePath)/.git/refs/heads")
        })

        let gitHeadChange = events.first(where: {
            $0.path.contains("\(self.folderUrl.relativePath)/.git/HEAD")
        })

        let gitConfigChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git/config"
        })

        let gitModulesChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.gitmodules"
        })

        if !notGitChanges.isEmpty || gitIndexChange != nil {
            Task {
                await self.sourceControlCoordinator?.refreshAll()
            }
        }

        if gitStashChange != nil {
            Task {
                try await self.sourceControlCoordinator?.primaryRepository?.refreshStashEntries()
            }
        }

        if gitBranchChange != nil {
            Task {
                await self.sourceControlCoordinator?.primaryRepository?.refreshBranches()
            }
        }

        if gitHeadChange != nil {
            Task {
                await self.sourceControlCoordinator?.primaryRepository?.refreshCurrentBranch()
            }
        }

        if gitConfigChange != nil {
            Task {
                try await self.sourceControlCoordinator?.primaryRepository?.refreshRemotes()
            }
        }

        if gitModulesChange != nil {
            Task {
                await self.sourceControlCoordinator?.rescan()
            }
        }

        if gitFolderChange != nil {
            Task {
                try await self.sourceControlCoordinator?.primaryRepository?.validate()
            }
        }
    }

    /// Creates or deletes children of the ``CEWorkspaceFile`` so that they are accurate with the file system,
    /// instead of creating an entirely new ``CEWorkspaceFile``. Can optionally run a deep rebuild.
    ///
    /// This method will return immediately if the given file item is not a directory.
    /// This will also only rebuild *already cached* directories.
    /// - Parameters:
    ///   - fileItem: The ``CEWorkspaceFile``  to correct the children of
    ///   - deep: Set to `true` if this should perform the rebuild recursively.
    func rebuildFiles(fromItem fileItem: CEWorkspaceFile, deep: Bool = false) throws {
        // Do not index directories that are not already loaded.
        guard childrenMap[fileItem.id] != nil else { return }

        // get the actual directory children
        let directoryContentsUrls = try fileManager.contentsOfDirectory(
            at: fileItem.resolvedURL,
            includingPropertiesForKeys: nil
        )

        // test for deleted children, and remove them from the index
        // Folders may or may not have slash at the end, this will normalize check
        let directoryContentsUrlsRelativePaths = directoryContentsUrls.map({ $0.relativePath })
        for (idx, oldURL) in (childrenMap[fileItem.id] ?? []).map({ URL(filePath: $0) }).enumerated().reversed()
        where !directoryContentsUrlsRelativePaths.contains(oldURL.relativePath) {
            flattenedFileItems.removeValue(forKey: oldURL.relativePath)
            childrenMap[fileItem.id]?.remove(at: idx)
        }

        // test for new children, and index them
        for newContent in directoryContentsUrls {
            // if the child has already been indexed, continue to the next item.
            guard !ignoredFilesAndFolders.contains(newContent.lastPathComponent) &&
                    !(childrenMap[fileItem.id]?.contains(newContent.relativePath) ?? true) else { continue }

            if fileManager.fileExists(atPath: newContent.path) {
                let newFileItem = createChild(newContent, forParent: fileItem)
                flattenedFileItems[newFileItem.id] = newFileItem
                childrenMap[fileItem.id]?.append(newFileItem.id)
            }
        }

        childrenMap[fileItem.id] = childrenMap[fileItem.id]?
            .map { URL(filePath: $0) }
            .sortItems(foldersOnTop: true)
            .map { $0.relativePath }

        if deep && childrenMap[fileItem.id] != nil {
            for child in (childrenMap[fileItem.id] ?? []).compactMap({ flattenedFileItems[$0] }) {
                try rebuildFiles(fromItem: child)
            }
        }
    }

    /// Notify observers that an update occurred in the watched files.
    /// - Parameter statusOnly: When `true`, only the item's status changed; observers shouldn't reload children.
    func notifyObservers(updatedItems: Set<CEWorkspaceFile>, statusOnly: Bool = false) {
        observers.allObjects.reversed().forEach { delegate in
            guard let delegate = delegate as? CEWorkspaceFileManagerObserver else {
                observers.remove(delegate)
                return
            }
            if statusOnly {
                delegate.fileManagerStatusUpdated(updatedItems: updatedItems)
            } else {
                delegate.fileManagerUpdated(updatedItems: updatedItems)
            }
        }
    }

    /// Add an observer for file system events.
    /// - Parameter observer: The observer to add.
    func addObserver(_ observer: CEWorkspaceFileManagerObserver) {
        observers.add(observer as AnyObject)
    }

    /// Remove an observer for file system events.
    /// - Parameter observer: The observer to remove.
    func removeObserver(_ observer: CEWorkspaceFileManagerObserver) {
        observers.remove(observer as AnyObject)
    }
}
