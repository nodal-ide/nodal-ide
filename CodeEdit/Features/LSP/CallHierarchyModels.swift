//
//  CallHierarchyModels.swift
//  CodeEdit
//
//  Domain models for the LSP call hierarchy (incoming/outgoing call tree).
//

import Foundation
import LanguageServerProtocol

/// The direction of a call-hierarchy query.
enum CallHierarchyDirection {
    /// Functions/methods that call the item.
    case incoming
    /// Functions/methods called by the item.
    case outgoing
}

/// A node in the call hierarchy: a callable symbol plus the opaque server token needed to query its calls.
struct CallHierarchyEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String?
    let kind: SymbolKind?
    let fileURL: URL?
    let line: Int
    let column: Int
    /// The original LSP item, needed to request incoming/outgoing calls.
    let item: CallHierarchyItem
}

/// A single call in the hierarchy (the caller for incoming, the callee for outgoing).
struct CallHierarchyCall: Identifiable, Hashable {
    let id: String
    let entry: CallHierarchyEntry
    /// Ranges in the *calling* document where the call occurs.
    let callRanges: [LSPRange]
}
