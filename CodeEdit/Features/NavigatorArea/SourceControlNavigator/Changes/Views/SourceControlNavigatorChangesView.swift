//
//  SourceControlNavigatorChangesView.swift
//  CodeEdit
//
//  Created by Nanashi Li on 2022/05/20.
//

import SwiftUI

struct SourceControlNavigatorChangesView: View {
    @EnvironmentObject var sourceControlManager: SourceControlManager
    @EnvironmentObject var workspace: WorkspaceDocument

    private var coordinator: SourceControlCoordinator? {
        workspace.sourceControlCoordinator
    }

    private var isMultiRepo: Bool {
        (coordinator?.repositories.count ?? 0) > 1
    }

    var hasRemotes: Bool {
        !sourceControlManager.remotes.isEmpty
    }

    var hasUnsyncedCommits: Bool {
        sourceControlManager.numberOfUnsyncedCommits.ahead > 0
        || sourceControlManager.numberOfUnsyncedCommits.behind > 0
    }

    var hasCurrentBranch: Bool {
        (sourceControlManager.currentBranch != nil && sourceControlManager.currentBranch?.upstream == nil)
    }

    var hasChanges: Bool {
        !sourceControlManager.changedFiles.isEmpty
    }

    var body: some View {
        if isMultiRepo, let coordinator {
            multiRepoBody(coordinator: coordinator)
        } else {
            singleRepoBody
        }
    }

    @ViewBuilder
    private func multiRepoBody(coordinator: SourceControlCoordinator) -> some View {
        List {
            ForEach(coordinator.repositories, id: \.workspaceURL) { manager in
                SourceControlNavigatorChangesSection(manager: manager)
                    .environmentObject(workspace)
            }
        }
        .environment(\.defaultMinListRowHeight, 22)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var singleRepoBody: some View {
        VStack(alignment: .center, spacing: 0) {
            if hasChanges || !hasRemotes || (!hasChanges && (hasUnsyncedCommits || hasCurrentBranch)) {
                VStack(spacing: 8) {
                    Divided {
                        if hasRemotes && (hasUnsyncedCommits || hasCurrentBranch) {
                            SourceControlNavigatorSyncView(sourceControlManager: sourceControlManager)
                        }
                        if hasChanges {
                            SourceControlNavigatorChangesCommitView()
                        }
                        if !hasRemotes {
                            SourceControlNavigatorNoRemotesView()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider()
            }
            if hasChanges {
                SourceControlNavigatorChangesList()
            } else {
                CEContentUnavailableView("No Changes")
            }
        }
        .frame(maxHeight: .infinity)
        .task {
            await sourceControlManager.refreshAllChangedFiles()
            await sourceControlManager.refreshNumberOfUnsyncedCommits()
        }
    }
}
