//
//  LanguageServerSettings.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/2/25.
//

import Foundation

extension SettingsData {
    struct LanguageServerSettings: Codable, Hashable, SearchableSettingsPage {

        /// The search keys
        var searchKeys: [String] {
            [
                "Language Servers",
                "LSP Binaries",
                "Internal Languages",
                "Linters",
                "Formatters",
                "Debug Protocol",
                "DAP",
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// Stores the currently installed language servers. The key is the name of the language server.
        var installedLanguageServers: [String: InstalledLanguageServer] = [:]

        /// Default initializer
        init() {
            self.installedLanguageServers = [:]
        }

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.installedLanguageServers = try container.decodeIfPresent(
                [String: InstalledLanguageServer].self,
                forKey: .installedLanguageServers
            ) ?? [:]
        }
    }

    struct InstalledLanguageServer: Codable, Hashable {
        let packageName: String
        var isEnabled: Bool
        let version: String
        /// The language identifiers this server provides (e.g. `typescript`, `javascript`).
        var languages: [String]
        /// The absolute path to the server's executable.
        var executablePath: String
        /// Launch arguments for the server. `nil` means "not resolved yet" (see `RegistryManager`).
        var arguments: [String]?

        init(
            packageName: String,
            isEnabled: Bool,
            version: String,
            languages: [String] = [],
            executablePath: String = "",
            arguments: [String]? = nil
        ) {
            self.packageName = packageName
            self.isEnabled = isEnabled
            self.version = version
            self.languages = languages
            self.executablePath = executablePath
            self.arguments = arguments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.packageName = try container.decode(String.self, forKey: .packageName)
            self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
            self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
            self.languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
            self.executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
            self.arguments = try container.decodeIfPresent([String].self, forKey: .arguments)
        }
    }
}
