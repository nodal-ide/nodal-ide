import SwiftUI

struct SourceControlNavigatorChangesSection: View {
    @ObservedObject var manager: SourceControlManager
    @State private var isExpanded: Bool

    init(manager: SourceControlManager) {
        self.manager = manager
        _isExpanded = State(initialValue: !manager.changedFiles.isEmpty)
    }

    private var hasRemotes: Bool { !manager.remotes.isEmpty }
    private var hasUnsyncedCommits: Bool {
        manager.numberOfUnsyncedCommits.ahead > 0 || manager.numberOfUnsyncedCommits.behind > 0
    }
    private var hasCurrentBranch: Bool {
        manager.currentBranch != nil && manager.currentBranch?.upstream == nil
    }
    private var hasChanges: Bool { !manager.changedFiles.isEmpty }
    private var showsControls: Bool {
        hasChanges || !hasRemotes || (hasUnsyncedCommits || hasCurrentBranch)
    }

    var body: some View {
        Section {
            if isExpanded {
                sectionContent
            }
        } header: {
            sectionHeader
        }
        .environmentObject(manager)
        .onChange(of: hasChanges) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded = newValue
            }
        }
    }

    private var sectionHeader: some View {
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
                    .lineLimit(1)
                Spacer(minLength: 6)
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
        .help(manager.workspaceURL.path(percentEncoded: false))
    }

    @ViewBuilder private var sectionContent: some View {
        if showsControls {
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
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }

        if hasChanges {
            ForEach($manager.changedFiles) { $file in
                GitChangedFileListView(changedFile: $file)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, -1)
                    .tag(file)
                    .contextMenu {
                        SourceControlNavigatorChangesContextMenu(
                            files: [file],
                            sourceControlManager: manager
                        )
                    }
                    .onTapGesture(count: 2) {
                        open(file)
                    }
            }
        } else {
            Text("No Changes")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
        }
    }

    private func open(_ file: GitChangedFile) {
        guard let ceFile = manager.fileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        DispatchQueue.main.async {
            manager.editorManager.openTab(item: ceFile, asTemporary: true)
        }
    }
}
