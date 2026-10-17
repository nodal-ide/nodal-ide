//
//  DeveloperSettings.swift
//  CodeEdit
//
//  Created by Abe Malla on 5/15/24.
//

import Foundation

extension SettingsData {
    struct DeveloperSettings: Codable, Hashable, SearchableSettingsPage {

        /// The search keys
        var searchKeys: [String] {
            [
                "Developer",
                "Language Server Protocol",
                "LSP Binaries",
                "Show Internal Development Inspector"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// A dictionary that stores a file type and a path to an LSP binary
        var lspBinaries: [String: String] = [:]

        /// A dictionary that stores a debug adapter id and the path to its executable.
        var debugAdapters: [String: String] = [:]

        /// Optional extra command-line arguments per debug adapter id (space-separated).
        var debugAdapterArguments: [String: String] = [:]

        /// Optional launch arguments per language server (space-separated), keyed by package name or language id.
        var lspServerArguments: [String: String] = [:]

        /// Global default runtime versions, keyed by runtime kind (`php`, `node`).
        var defaultRuntimeVersions: [String: String] = [:]

        /// The client port Xdebug connects to (PHP debugging). Defaults to Xdebug 3's `9003`.
        var phpDebugClientPort: Int = 9003

        /// Language identifiers that should use the app's built-in (native) language implementation instead of an
        /// external language server. Defaults to `php`, which ships with a native engine.
        var internalLanguages: [String] = InternalLanguage.defaultEnabledIdentifiers

        /// Toggle for showing the internal development inspector
        var showInternalDevelopmentInspector: Bool = false

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.lspBinaries = try container.decodeIfPresent(
                [String: String].self,
                forKey: .lspBinaries
            ) ?? [:]

            self.debugAdapters = try container.decodeIfPresent(
                [String: String].self,
                forKey: .debugAdapters
            ) ?? [:]

            self.debugAdapterArguments = try container.decodeIfPresent(
                [String: String].self,
                forKey: .debugAdapterArguments
            ) ?? [:]

            self.lspServerArguments = try container.decodeIfPresent(
                [String: String].self,
                forKey: .lspServerArguments
            ) ?? [:]

            self.defaultRuntimeVersions = try container.decodeIfPresent(
                [String: String].self,
                forKey: .defaultRuntimeVersions
            ) ?? [:]

            self.phpDebugClientPort = try container.decodeIfPresent(
                Int.self,
                forKey: .phpDebugClientPort
            ) ?? 9003

            self.internalLanguages = try container.decodeIfPresent(
                [String].self,
                forKey: .internalLanguages
            ) ?? InternalLanguage.defaultEnabledIdentifiers

            self.showInternalDevelopmentInspector = try container.decodeIfPresent(
                Bool.self,
                forKey: .showInternalDevelopmentInspector
            ) ?? false
        }
    }
}
