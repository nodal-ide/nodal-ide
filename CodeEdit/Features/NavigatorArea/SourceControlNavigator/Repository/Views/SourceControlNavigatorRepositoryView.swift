//
//  SourceControlNavigatorRepositoryView.swift
//  CodeEdit
//
//  Created by Nanashi Li on 2022/05/20.
//

import SwiftUI
import CodeEditSymbols

struct SourceControlNavigatorRepositoryView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    private var coordinator: SourceControlCoordinator? {
        workspace.sourceControlCoordinator
    }

    var body: some View {
        if let coordinator, coordinator.repositories.count > 1 {
            List {
                ForEach(coordinator.repositories, id: \.workspaceURL) { sourceControlManager in
                    Section {
                        SourceControlNavigatorRepositoryContent(
                            sourceControlManager: sourceControlManager,
                            style: .section
                        )
                    } header: {
                        RepositorySectionHeader(
                            sourceControlManager: sourceControlManager
                        )
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 22)
        } else if let sourceControlManager = coordinator?.primaryRepository {
            SourceControlNavigatorRepositoryContent(
                sourceControlManager: sourceControlManager,
                style: .list
            )
        }
    }
}

private struct RepositorySectionHeader: View {
    @ObservedObject var sourceControlManager: SourceControlManager

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: sourceControlManager.isSubmodule ? "arrow.triangle.branch" : "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(sourceControlManager.repoDisplayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(sourceControlManager.workspaceURL.path(percentEncoded: false))
    }
}

struct SourceControlNavigatorRepositoryContent: View {
    enum Style {
        case list
        case section
    }

    @ObservedObject var sourceControlManager: SourceControlManager
    let style: Style

    @State var selection = Set<String>()
    @State var showNewBranch: Bool = false
    @State var showRenameBranch: Bool = false
    @State var fromBranch: GitBranch?
    @State var expandedIds = [String: Bool]()
    @State var applyStashedChangesIsPresented: Bool = false
    @State var isPresentingConfirmDeleteBranch: Bool = false
    @State var branchToDelete: GitBranch?
    @State var isPresentingConfirmDeleteStashEntry: Bool = false
    @State var stashEntryToApply: GitStashEntry?
    @State var stashEntryToDelete: GitStashEntry?
    @State var isPresentingConfirmDeleteRemote: Bool = false
    @State var remoteToDelete: GitRemote?
    @State var keepStashAfterApplying: Bool = true

    var body: some View {
        content
            .environmentObject(sourceControlManager)
            .sheet(isPresented: $showNewBranch) {
                SourceControlNewBranchView(fromBranch: $fromBranch)
            }
            .sheet(isPresented: $showRenameBranch) {
                SourceControlRenameBranchView(fromBranch: $fromBranch)
            }
            .alert(
                sourceControlManager.changedFiles.isEmpty
                ? "Do you want to apply stashed changes?"
                : "The local repository has uncommitted changes.",
                isPresented: $applyStashedChangesIsPresented
            ) {
                if sourceControlManager.changedFiles.isEmpty {
                    Button("Apply") {
                        guard let stashEntry = stashEntryToApply else { return }
                        Task {
                            do {
                                try await sourceControlManager.applyStashEntry(stashEntry: stashEntry)
                            } catch {
                                await sourceControlManager.showAlertForError(
                                    title: "Failed to apply stash",
                                    error: error
                                )
                            }
                            applyStashedChangesIsPresented = false
                            stashEntryToApply = nil
                        }
                    }
                    Button("Apply and Delete") {
                        guard let stashEntry = stashEntryToApply else { return }
                        Task {
                            do {
                                try await sourceControlManager.applyStashEntry(stashEntry: stashEntry)
                                try await sourceControlManager.deleteStashEntry(stashEntry: stashEntry)
                            } catch {
                                await sourceControlManager.showAlertForError(
                                    title: "Failed to apply stash",
                                    error: error
                                )
                            }
                            applyStashedChangesIsPresented = false
                            stashEntryToApply = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("Okay", role: .cancel) {}
                }
            } message: {
                sourceControlManager.changedFiles.isEmpty
                ? Text("Applying the stashed changes will restore modifications to files in your local repository.")
                : Text("Try committing or discarding the changes.")
            }
            .confirmationDialog(
                "Do you want to delete the branch “\(branchToDelete?.name ?? "")”?",
                isPresented: $isPresentingConfirmDeleteBranch
            ) {
                Button("Delete") {
                    guard let branch = branchToDelete else { return }
                    Task {
                        do {
                            try await sourceControlManager.deleteBranch(branch: branch)
                        } catch {
                            await sourceControlManager.showAlertForError(
                                title: "Failed to delete",
                                error: error
                            )
                        }
                        branchToDelete = nil
                    }
                }
            } message: {
                Text("The branch will be removed from the repository. You can’t undo this action.")
            }
            .confirmationDialog(
                "Do you want to delete the stash “\(stashEntryToDelete?.message ?? "")”?",
                isPresented: $isPresentingConfirmDeleteStashEntry
            ) {
                Button("Delete") {
                    guard let stashEntry = stashEntryToDelete else { return }
                    Task {
                        do {
                            try await sourceControlManager.deleteStashEntry(stashEntry: stashEntry)
                        } catch {
                            await sourceControlManager.showAlertForError(
                                title: "Failed to delete",
                                error: error
                            )
                        }
                        stashEntryToDelete = nil
                    }
                }
            } message: {
                Text("The stash will be removed from the repository. You can’t undo this action.")
            }
            .confirmationDialog(
                "Do you want to delete the remote “\(remoteToDelete?.name ?? "")”?",
                isPresented: $isPresentingConfirmDeleteRemote
            ) {
                Button("Delete") {
                    guard let remote = remoteToDelete else { return }
                    Task {
                        do {
                            try await sourceControlManager.deleteRemote(remote: remote)
                        } catch {
                            await sourceControlManager.showAlertForError(
                                title: "Failed to delete",
                                error: error
                            )
                        }
                        remoteToDelete = nil
                    }
                }
            } message: {
                Text("The remote will be removed from the repository. You can’t undo this action.")
            }
            .task {
                await refreshRepository()
            }
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .list:
            List(selection: $selection) {
                outlineGroups
                    .listRowSeparator(.hidden)
            }
            .environment(\.defaultMinListRowHeight, 22)
            .contextMenu(
                forSelectionType: RepoOutlineGroupItem.ID.self,
                menu: { items in
                    listContextMenu(for: items)
                }
            )
        case .section:
            VStack(alignment: .leading, spacing: 0) {
                outlineGroups
            }
        }
    }

    private var outlineGroups: some View {
        ForEach(outlineGroupData, id: \.id) { item in
            CEOutlineGroup(
                item,
                id: \.id,
                defaultExpanded: true,
                expandedIds: $expandedIds,
                children: \.children,
                content: { item in
                    rowContent(for: item)
                }
            )
        }
    }

    @ViewBuilder
    private func rowContent(for item: RepoOutlineGroupItem) -> some View {
        if style == .section {
            SourceControlNavigatorRepositoryItem(item: item)
                .contextMenu {
                    itemContextMenu(for: item)
                }
        } else {
            SourceControlNavigatorRepositoryItem(item: item)
        }
    }

    @ViewBuilder
    private func listContextMenu(for items: Set<RepoOutlineGroupItem.ID>) -> some View {
        if items.count == 1,
           let id = items.first,
           let item = findItem(by: id, in: outlineGroupData) {
            itemContextMenu(for: item)
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: RepoOutlineGroupItem) -> some View {
        if let branch = item.branch ?? sourceControlManager.currentBranch {
            contextMenu(for: item, branch: branch)
        } else if sourceControlManager.isSubmodule {
            submoduleContextMenu()
        }
    }

    private func refreshRepository() async {
        await sourceControlManager.refreshBranches()
        await sourceControlManager.refreshCurrentBranch()
        try? await sourceControlManager.refreshRemotes()
        try? await sourceControlManager.refreshStashEntries()
    }

    func findItem(by id: String, in items: [RepoOutlineGroupItem]) -> RepoOutlineGroupItem? {
        for item in items {
            if item.id == id {
                return item
            } else if let children = item.children, let found = findItem(by: id, in: children) {
                return found
            }
        }
        return nil
    }
}
