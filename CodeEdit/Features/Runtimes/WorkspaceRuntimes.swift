//
//  WorkspaceRuntimes.swift
//  CodeEdit
//
//  Per-project runtime selection (stored in the project settings JSON).
//

import Foundation

/// A runtime selection for one kind (a version and optional package manager).
struct RuntimeSelection: Codable, Hashable {
    var version: String?
    var packageManager: String?

    var isEmpty: Bool {
        (version?.isEmpty ?? true) && (packageManager?.isEmpty ?? true)
    }
}

/// The `runtimes` section of the project settings.
struct WorkspaceRuntimes: Codable, Hashable {
    var php: RuntimeSelection = .init()
    var node: RuntimeSelection = .init()

    func selection(for kind: RuntimeKind) -> RuntimeSelection {
        switch kind {
        case .php: return php
        case .node: return node
        case .typescript: return .init()
        }
    }

    mutating func setSelection(_ selection: RuntimeSelection, for kind: RuntimeKind) {
        switch kind {
        case .php: php = selection
        case .node: node = selection
        case .typescript: break
        }
    }

    var isEmpty: Bool { php.isEmpty && node.isEmpty }
}
