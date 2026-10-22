//
//  ExtensionsSettings.swift
//  CodeEdit
//

import Foundation

extension SettingsData {
    /// Installed language-extension preferences (edited from the Extensions window, not a settings page).
    struct ExtensionsSettings: Codable, Hashable {
        /// Ids of installed extensions the user has disabled. Extensions are enabled by default.
        var disabledExtensions: [String] = []

        /// Native grammar consent: `<extension id>/<grammar path>` → the approved SHA-256.
        var nativeGrammarConsent: [String: String] = [:]

        /// Package source configuration; secrets are stored in Keychain, never in settings.
        var sources: [ExtensionSource] = []

        /// The Git checkout used by the editor to package and publish releases.
        var registry: ExtensionRegistryConfiguration?

        /// Whether the built-in extension source has been initialized.
        var hasSeededDefaultSource = false

        /// Global rollout switches for extension-contributed syntax.
        var syntaxPacksEnabled = true
        var nativeGrammarsEnabled = true

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hasSeededDefaultSource = try container.decodeIfPresent(
                Bool.self,
                forKey: .hasSeededDefaultSource
            ) ?? false
            self.disabledExtensions = try container.decodeIfPresent(
                [String].self,
                forKey: .disabledExtensions
            ) ?? []
            self.nativeGrammarConsent = try container.decodeIfPresent(
                [String: String].self,
                forKey: .nativeGrammarConsent
            ) ?? [:]
            self.sources = try container.decodeIfPresent([ExtensionSource].self, forKey: .sources) ?? []
            self.registry = try container.decodeIfPresent(
                ExtensionRegistryConfiguration.self,
                forKey: .registry
            )
            self.syntaxPacksEnabled = try container.decodeIfPresent(
                Bool.self,
                forKey: .syntaxPacksEnabled
            ) ?? true
            self.nativeGrammarsEnabled = try container.decodeIfPresent(
                Bool.self,
                forKey: .nativeGrammarsEnabled
            ) ?? true
        }
    }
}
