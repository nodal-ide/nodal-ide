import SwiftUI
import CodeEditLang
import CodeEditSourceEditor

struct ReferencesNavigatorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        ReferencesNavigatorContent(session: workspace.referencesSession)
    }
}

@MainActor
private struct ReferencesNavigatorContent: View {
    @ObservedObject var session: ReferencesSession
    @EnvironmentObject private var workspace: WorkspaceDocument

    @State private var filter = ReferencesFilter()
    @State private var expanded: Set<String> = []
    @State private var selectedID: String?
    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ReferencesHeaderView(
                session: session,
                filter: $filter,
                hasCurrentFile: currentFile != nil
            )
            Divider()
            content
        }
        .onChange(of: session.target) { _, _ in
            filter = ReferencesFilter()
            expanded = Set(session.groups.map(\.id))
            selectedID = nil
        }
        .onChange(of: session.groups) { _, groups in
            expanded.formUnion(groups.map(\.id))
        }
        .onChange(of: filter) { _, _ in
            if let selectedID, !visibleReferences.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            ReferencesEmptyStateView(
                title: "Find References",
                description: "Place the cursor on a symbol, then choose Editor ▸ Find All References (⇧F12).",
                systemImage: "text.magnifyingglass"
            )
        case .searching:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(session.target.map { "Searching for references to “\($0.identifier)”…" } ?? "Searching…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results:
            resultsContent
        case .unsupported(let reason):
            ReferencesEmptyStateView(
                title: "References Unavailable",
                description: reason,
                systemImage: "questionmark.circle"
            )
        case .failed(let error):
            ReferencesEmptyStateView(
                title: "References Failed",
                description: error.message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Try Again",
                action: { session.refresh() }
            )
        }
    }

    private var resultsContent: some View {
        VStack(spacing: 0) {
            if !session.isComplete {
                partialBanner
            }
            if visibleGroups.isEmpty {
                if session.totalCount == 0 {
                    ReferencesEmptyStateView(
                        title: "No References",
                        description: emptyDescription,
                        systemImage: "arrow.turn.up.right"
                    )
                } else {
                    ReferencesEmptyStateView(
                        title: "No Matches",
                        description: "No references match the current filter or scope.",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
            } else {
                referenceList
            }
        }
    }

    private var partialBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text("Partial results — some files weren’t searched.")
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Refresh") { session.refresh() }
                .buttonStyle(.link)
                .font(.system(size: 10))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.12))
    }

    private var referenceList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(visibleGroups) { group in
                        Section {
                            if expanded.contains(group.id) {
                                ForEach(group.exactReferences) { reference in
                                    row(reference)
                                }
                                if !group.heuristicReferences.isEmpty {
                                    ReferencesHeuristicHeaderView(count: group.heuristicReferences.count)
                                    ForEach(group.heuristicReferences) { reference in
                                        row(reference)
                                    }
                                }
                            }
                        } header: {
                            ReferencesFileHeaderView(
                                group: group,
                                isExpanded: expanded.contains(group.id)
                            ) {
                                toggle(group.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onMoveCommand(perform: move)
            .onKeyPress(.return) {
                openSelected()
                return .handled
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .onAppear { isListFocused = true }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func row(_ reference: EditorReference) -> some View {
        ReferencesRowView(reference: reference, isSelected: selectedID == reference.id)
            .id(reference.id)
            .onTapGesture {
                selectedID = reference.id
                reveal(reference)
            }
    }

    private var emptyDescription: String {
        guard let identifier = session.target?.identifier else {
            return "No references were found."
        }
        return "No references to “\(identifier)” were found in this workspace."
    }

    private var currentFile: URL? {
        guard let tab = workspace.editorManager?.activeEditor.selectedTab else { return nil }
        return (tab.file.fileDocument?.fileURL ?? tab.file.url).standardizedFileURL
    }

    private var visibleGroups: [ReferenceFileGroup] {
        filter.groups(from: session.groups, currentFile: currentFile)
    }

    private var visibleReferences: [EditorReference] {
        visibleGroups.flatMap(\.references)
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        let references = visibleReferences
        guard !references.isEmpty else { return }
        let index = references.firstIndex { $0.id == selectedID }
        switch direction {
        case .up:
            selectedID = references[max(0, (index ?? 0) - 1)].id
        case .down:
            selectedID = references[min(references.count - 1, (index ?? -1) + 1)].id
        default:
            break
        }
    }

    private func openSelected() {
        guard let reference = visibleReferences.first(where: { $0.id == selectedID }) else { return }
        reveal(reference)
    }

    private func reveal(_ reference: EditorReference) {
        if workspace.editorManager?.reveal(
            url: reference.fileURL,
            line: reference.line,
            column: reference.column
        ) == true {
            if let controller = workspace.editorManager?.activeEditor.selectedTab?.rangeTranslator.controller {
                controller.setCursorPositions(
                    [CursorPosition(range: reference.range)],
                    scrollToVisible: true
                )
            }
            return
        }

        CodeEditDocumentController.shared.openDocument(
            withContentsOf: reference.fileURL,
            display: true
        ) { document, _, _ in
            (document as? CodeFileDocument)?.openOptions = .init(
                cursorPositions: [CursorPosition(range: reference.range)]
            )
        }
    }
}
