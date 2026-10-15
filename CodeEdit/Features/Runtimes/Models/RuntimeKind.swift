//
//  RuntimeKind.swift
//  CodeEdit
//
//  Web runtimes managed by the Runtime Manager.
//

import Foundation

enum RuntimeKind: String, CaseIterable, Identifiable, Codable {
    case php
    case node
    case typescript

    var id: String { rawValue }

    /// Kinds the Runtime Manager window manages directly (TypeScript rides on Node).
    static var manageable: [RuntimeKind] { [.php, .node] }

    var title: String {
        switch self {
        case .php: return "PHP"
        case .node: return "Node.js"
        case .typescript: return "TypeScript"
        }
    }

    var systemImage: String {
        switch self {
        case .php: return "p.circle.fill"
        case .node: return "hexagon.fill"
        case .typescript: return "t.circle.fill"
        }
    }

    /// The primary executable for the runtime.
    var executableName: String {
        switch self {
        case .php: return "php"
        case .node: return "node"
        case .typescript: return "tsc"
        }
    }
}

/// Where an installed runtime came from.
enum RuntimeVersionSource: String, Codable {
    /// Installed by CodeEdit under `~/.codeedit/runtimes`.
    case managed
    case brew
    case system
    case nvm
    case fnm
    case volta

    var title: String {
        switch self {
        case .managed: return "Managed"
        case .brew: return "Homebrew"
        case .system: return "System"
        case .nvm: return "nvm"
        case .fnm: return "fnm"
        case .volta: return "Volta"
        }
    }

    /// Preference when the same version is found from multiple sources (lower wins).
    var priority: Int {
        switch self {
        case .managed: return 0
        case .brew, .nvm, .fnm, .volta: return 1
        case .system: return 2
        }
    }
}
