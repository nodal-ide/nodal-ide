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
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ShellEnvironment.augmentedPath()

        var configs: [LanguageIdentifier: LanguageServerBinary] = [:]
        for server in installedServers.values where server.isEnabled && !server.executablePath.isEmpty {
            let args = Self.launchArguments(for: server.packageName)
            for language in server.languages {
                guard let id = Self.languageIdentifier(from: language) else { continue }
                configs[id] = LanguageServerBinary(execPath: server.executablePath, args: args, env: environment)
            }
        }
        for binary in lspBinaries {
            if let language = LanguageIdentifier(rawValue: binary.key) {
                configs[language] = LanguageServerBinary(
                    execPath: binary.value,
                    args: Self.launchArguments(for: binary.key),
                    env: environment
                )
            }
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

    /// Default launch arguments for well-known language servers (most expect `--stdio`).
    private static let defaultServerArguments: [String: [String]] = [
        "typescript-language-server": ["--stdio"],
        "vscode-html-language-server": ["--stdio"],
        "vscode-css-language-server": ["--stdio"],
        "vscode-json-language-server": ["--stdio"],
        "vscode-eslint-language-server": ["--stdio"],
        "yaml-language-server": ["--stdio"],
        "pyright": ["--stdio"],
        "docker-langserver": ["--stdio"],
        "bash-language-server": ["start"],
        "lua-language-server": [],
        "gopls": [],
        "rust-analyzer": [],
        "clangd": [],
        "pylsp": []
    ]

    /// The launch arguments for a server, honoring the user override then known defaults (else `--stdio`).
    private static func launchArguments(for key: String) -> [String] {
        let override = Settings.shared.preferences.developerSettings.lspServerArguments[key]
        if let override, !override.isEmpty {
            return override.split(separator: " ").map(String.init)
        }
        return defaultServerArguments[key] ?? ["--stdio"]
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
