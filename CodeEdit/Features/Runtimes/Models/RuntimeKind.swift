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

    var title: String {
        switch self {
        case .php: return "PHP"
        case .node: return "Node.js"
        case .typescript: return "TypeScript"
        }
    }

    var systemImage: String {
        switch self {
        case .php: return "elephant"
        case .node: return "hexagon"
        case .typescript: return "ts.circle"
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
}
