//
//  LSPEditorActions+CallHierarchy.swift
//  CodeEdit
//
//  Call hierarchy requests backed by the language server.
//

import Foundation
import LanguageServerProtocol

extension LSPEditorActions {
    /// Prepares a call hierarchy at the cursor and returns the items (usually one) it applies to.
    static func prepareCallHierarchy(workspace: WorkspaceDocument?) async -> [CallHierarchyEntry] {
        guard let workspace,
              let context = activeContext(workspace: workspace),
              let position = position(in: context.controller.textView) else {
            return []
        }
        guard let items = try? await context.server.requestPrepareCallHierarchy(
            for: context.fileURL.lspURI,
            position: position
        ) else {
            return []
        }
        return items.map(callHierarchyEntry(from:))
    }

    /// Fetches the incoming or outgoing calls for a prepared call-hierarchy entry.
    static func callHierarchyCalls(
        for entry: CallHierarchyEntry,
        direction: CallHierarchyDirection,
        workspace: WorkspaceDocument?
    ) async -> [CallHierarchyCall] {
        guard let server = activeContext(workspace: workspace)?.server else {
            return []
        }
        switch direction {
        case .incoming:
            guard let calls = try? await server.requestCallHierarchyIncomingCalls(entry.item) else {
                return []
            }
            return calls.map { call in
                CallHierarchyCall(
                    id: "in:\(call.from.uri):\(call.from.selectionRange.start.line):\(call.from.name)",
                    entry: callHierarchyEntry(from: call.from),
                    callRanges: call.fromRanges
                )
            }
        case .outgoing:
            guard let calls = try? await server.requestCallHierarchyOutgoingCalls(entry.item) else {
                return []
            }
            return calls.map { call in
                CallHierarchyCall(
                    id: "out:\(call.to.uri):\(call.to.selectionRange.start.line):\(call.to.name)",
                    entry: callHierarchyEntry(from: call.to),
                    callRanges: call.fromRanges
                )
            }
        }
    }

    private static func callHierarchyEntry(from item: CallHierarchyItem) -> CallHierarchyEntry {
        let start = item.selectionRange.start
        return CallHierarchyEntry(
            id: "\(item.uri):\(start.line):\(start.character):\(item.name)",
            name: item.name,
            detail: item.detail,
            kind: item.kind,
            fileURL: URL(string: item.uri),
            line: start.line,
            column: start.character,
            item: item
        )
    }
}
