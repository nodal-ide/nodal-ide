//
//  CallHierarchyViewModel.swift
//  CodeEdit
//
//  Backs the call-hierarchy panel: a lazily-expanded tree of callers/callees.
//

import Combine
import Foundation

/// A node in the call-hierarchy tree. Children (callers/callees) are fetched lazily on first expansion.
@MainActor
final class CallHierarchyNode: ObservableObject, Identifiable {
    let entry: CallHierarchyEntry
    var id: String { entry.id }

    @Published var expanded = false
    @Published var isLoading = false
    @Published var incoming: [CallHierarchyNode]?
    @Published var outgoing: [CallHierarchyNode]?

    private let workspace: WorkspaceDocument

    init(entry: CallHierarchyEntry, workspace: WorkspaceDocument) {
        self.entry = entry
        self.workspace = workspace
    }

    func toggleExpansion() {
        expanded.toggle()
        if expanded, incoming == nil, outgoing == nil, !isLoading {
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        let incomingCalls = await LSPEditorActions.callHierarchyCalls(
            for: entry, direction: .incoming, workspace: workspace
        )
        let outgoingCalls = await LSPEditorActions.callHierarchyCalls(
            for: entry, direction: .outgoing, workspace: workspace
        )
        incoming = incomingCalls.map { CallHierarchyNode(entry: $0.entry, workspace: workspace) }
        outgoing = outgoingCalls.map { CallHierarchyNode(entry: $0.entry, workspace: workspace) }
        isLoading = false
    }
}

/// The root view model for the call-hierarchy panel.
@MainActor
final class CallHierarchyViewModel: ObservableObject {
    @Published var roots: [CallHierarchyNode] = []
    @Published var isLoading = false
    @Published var isEmpty = false

    private let workspace: WorkspaceDocument

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    func prepare() async {
        isLoading = true
        let entries = await LSPEditorActions.prepareCallHierarchy(workspace: workspace)
        roots = entries.map { CallHierarchyNode(entry: $0, workspace: workspace) }
        isEmpty = entries.isEmpty
        isLoading = false
    }
}
