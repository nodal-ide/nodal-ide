//
//  LSPService+Configuration.swift
//  CodeEdit
//
//  Builds language-server configurations from installed servers + manual binaries.
//

import AppKit
import Foundation
import LanguageServerProtocol

extension LSPService {
    /// Rebuilds the language-server configurations from the enabled registry servers and the manual binaries.
    ///
    /// Manual developer-setting binaries take precedence over registry-installed servers. The spawned servers
    /// get an augmented `PATH` so `node`/`python`-based servers resolve their interpreter.
    func reloadConfigurations() {
        // Configurations changed: allow previously-failed servers to be retried.
        failedClientKeys.removeAll()

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ShellEnvironment.augmentedPath()

        var configs: [LanguageIdentifier: LanguageServerBinary] = [:]
        for server in installedServers.values where server.isEnabled && !server.executablePath.isEmpty {
            // Arguments are resolved at install time from the registry item's source type (see `RegistryManager`).
            let args = server.arguments ?? ["--stdio"]
            for language in server.languages {
                guard let id = Self.languageIdentifier(from: language) else { continue }
                configs[id] = LanguageServerBinary(execPath: server.executablePath, args: args, env: environment)
            }
        }
        for binary in lspBinaries {
            guard let language = LanguageIdentifier(rawValue: binary.key) else { continue }
            configs[language] = LanguageServerBinary(
                execPath: binary.value,
                args: Self.manualLaunchArguments(for: binary.key),
                env: environment
            )
        }

        // A TypeScript/JavaScript server also handles the JSX/TSX variants.
        if let typescript = configs[.typescript], configs[.typescriptreact] == nil {
            configs[.typescriptreact] = typescript
        }
        if let javascript = configs[.javascript], configs[.javascriptreact] == nil {
            configs[.javascriptreact] = javascript
        }

        languageConfigs = configs
    }

    /// Launch arguments for a manually-configured binary, honoring the user override then known defaults.
    private static func manualLaunchArguments(for key: String) -> [String] {
        let overrides = AppServices.settings.preferences.developerSettings.lspServerArguments
        if let override = overrides[key], !override.isEmpty {
            return override.split(separator: " ").map(String.init)
        }
        return RegistryManager.knownServerArguments[key] ?? ["--stdio"]
    }

    /// Maps a registry language name (often capitalized, e.g. `TypeScript`) to an LSP language identifier.
    private static func languageIdentifier(from name: String) -> LanguageIdentifier? {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
        if let id = LanguageIdentifier(rawValue: normalized) {
            return id
        }
        let aliases: [String: LanguageIdentifier] = [
            "typescriptreact": .typescriptreact,
            "javascriptreact": .javascriptreact,
            "ts": .typescript,
            "js": .javascript
        ]
        return aliases[normalized]
    }

    /// Reloads configurations and (re)starts servers for any already-open documents.
    func reloadConfigurationsAndRestart() {
        reloadConfigurations()
        for document in NSDocumentController.shared.documents {
            if let codeDocument = document as? CodeFileDocument {
                openDocument(codeDocument)
            }
        }
    }
}
