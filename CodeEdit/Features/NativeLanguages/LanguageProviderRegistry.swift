//
//  LanguageProviderRegistry.swift
//  CodeEdit
//
//  Native + extension language provider registry.
//

import Foundation
import CodeEditSourceEditor
import CodeEditLangPHP

/// The set of editor delegate protocols a language provider (or the aggregator) implements.
typealias LanguageDelegate = CodeSuggestionDelegate & JumpToDefinitionDelegate & HoverDelegate &
    SignatureHelpDelegate & CodeActionDelegate & DiagnosticsDelegate & SymbolsDelegate

/// Resolves the ordered list of ``LanguageProvider``s for an open file.
///
/// Order: user language extensions (highest) → built-in engine. The app registers extension
/// factories; the built-in engine for a language is added here.
final class LanguageProviderRegistry {
    static let shared = LanguageProviderRegistry()

    /// Factories that may contribute providers for a file. Registration lets the extension
    /// loader plug in without the registry knowing about it.
    private var extensionFactories: [(URL, URL) -> [any LanguageProvider]] = []

    private init() {}

    /// Registers a factory that can contribute providers for a file (called with file URL, workspace root).
    func registerExtensionFactory(_ factory: @escaping (URL, URL) -> [any LanguageProvider]) {
        extensionFactories.append(factory)
    }

    /// Returns providers for a file, ordered by priority (highest first).
    func providers(
        for file: URL,
        root: URL,
        languageID: String,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> [any LanguageProvider] {
        var providers: [any LanguageProvider] = []

        for factory in extensionFactories {
            providers.append(contentsOf: factory(file, root))
        }

        if languageID == "php",
           InternalLanguage.isEnabled(.php, in: Settings.shared.preferences.developerSettings) {
            // Fold declarative language-extension symbols into the workspace index so the built-in
            // engine completes/hovers/jumps to framework symbols too.
            let index = PHPWorkspaceIndex.shared.index(for: root)
            WorkspaceLanguageExtensions.shared.inject(into: index, root: root, language: "php")
            providers.append(PHPWorkspaceIndex.shared.provider(for: file, root: root, openLink: openLink))
        }

        return providers
    }

    /// Re-evaluates language extensions for a workspace after project settings change: removes the
    /// previously injected pack symbols from the index and re-injects with the new activation.
    func reloadExtensions(for root: URL) {
        LanguageExtensionStore.shared.reload()
        let index = PHPWorkspaceIndex.shared.index(for: root)
        for url in WorkspaceLanguageExtensions.shared.takeInjectedStubURLs(for: root) {
            index.removeFile(url)
        }
        WorkspaceLanguageExtensions.shared.reload()
        WorkspaceLanguageExtensions.shared.inject(into: index, root: root, language: "php")
    }
}
