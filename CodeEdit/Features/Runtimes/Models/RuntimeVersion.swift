//
//  RuntimeVersion.swift
//  CodeEdit
//
//  Runtime version models.
//

import Foundation

/// A runtime version found on the system (installed or adopted).
struct InstalledRuntime: Identifiable, Hashable {
    let kind: RuntimeKind
    let version: String
    let source: RuntimeVersionSource
    /// The directory containing the runtime's executables (used for PATH prepending).
    let executableDirectory: URL
    /// An identifier the provider needs to uninstall this runtime (e.g. a Homebrew formula).
    var installIdentifier: String?

    var id: String { "\(kind.rawValue):\(version):\(source.rawValue)" }
    var isManaged: Bool { source == .managed }

    /// Whether the app can uninstall this runtime (managed installs, or Homebrew formulae).
    var isRemovable: Bool {
        isManaged || (source == .brew && installIdentifier != nil)
    }

    /// The runtime's install root (the parent of its `bin` directory).
    var runtimeRoot: URL {
        executableDirectory.deletingLastPathComponent()
    }

    /// Locates a fixed executable inside this runtime's install (e.g. `sbin/php-fpm`), which keeps
    /// companion tools pinned to the same install as the interpreter instead of the global `PATH`.
    func executable(relativePath: String) -> URL {
        runtimeRoot.appending(path: relativePath)
    }
}

/// A version offered by a provider's catalog (may or may not be installed).
struct RuntimeVersion: Identifiable, Hashable, Codable {
    let version: String
    var isLTS: Bool?
    var releaseDate: Date?
    /// An identifier the provider needs to install this version (e.g. a Homebrew formula).
    var installIdentifier: String?
    /// The source it is installed as, if present on the system.
    var installedSource: RuntimeVersionSource?

    var id: String { version }
    var isInstalled: Bool { installedSource != nil }
}

/// Progress reported while installing a runtime.
struct RuntimeInstallProgress {
    enum Phase {
        case resolving
        case downloading
        case verifying
        case extracting
        case installing
        case done
        case failed

        var title: String {
            switch self {
            case .resolving: return "Resolving"
            case .downloading: return "Downloading"
            case .verifying: return "Verifying"
            case .extracting: return "Extracting"
            case .installing: return "Installing"
            case .done: return "Done"
            case .failed: return "Failed"
            }
        }
    }

    let phase: Phase
    /// Completion in `0...1`, if known.
    var fraction: Double?
    var message: String?
}
