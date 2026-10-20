import SwiftUI

struct SourceControlNavigatorChangesSection: View {
    @EnvironmentObject var workspace: WorkspaceDocument
    @ObservedObject var manager: SourceControlManager
    @State private var isExpanded: Bool = true

    var hasRemotes: Bool { !manager.remotes.isEmpty }
    var hasUnsyncedCommits: Bool {
        manager.numberOfUnsyncedCommits.ahead > 0 || manager.numberOfUnsyncedCommits.behind > 0
    }
    var hasCurrentBranch: Bool { manager.currentBranch != nil && manager.currentBranch?.upstream == nil }
    var hasChanges: Bool { !manager.changedFiles.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if isExpanded {
                sectionContent
            }
        }
    }

    @ViewBuilder private var sectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: manager.isSubmodule ? "arrow.triangle.branch" : "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(manager.repoDisplayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if hasChanges {
                    Text("\(manager.changedFiles.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder private var sectionContent: some View {
        VStack(spacing: 0) {
            if hasChanges || !hasRemotes || (!hasChanges && (hasUnsyncedCommits || hasCurrentBranch)) {
                VStack(spacing: 8) {
                    Divided {
                        if hasRemotes && (hasUnsyncedCommits || hasCurrentBranch) {
                            SourceControlNavigatorSyncView(sourceControlManager: manager)
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
                    .frame(minHeight: 60)
            }
        }
        .environmentObject(manager)
    }
}
