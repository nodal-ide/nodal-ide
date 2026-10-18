//
//  LanguageProviderRegistry.swift
//  CodeEdit
//
//  Native + extension language provider registry.
//

import Foundation
import LanguageServerProtocol
import CodeEditSourceEditor
import CodeEditLangPHP

/// The set of editor delegate protocols a language provider (or the aggregator) implements.
typealias LanguageDelegate = CodeSuggestionDelegate & JumpToDefinitionDelegate & HoverDelegate &
    SignatureHelpDelegate & CodeActionDelegate & DiagnosticsDelegate & SymbolsDelegate & InlayHintDelegate &
    FoldRangeDelegate & DocumentHighlightDelegate

/// Resolves the ordered list of ``LanguageProvider``s for an open file.
///
/// Order: extension providers (highest) → built-in engine.
final class LanguageProviderRegistry {
    static let shared = LanguageProviderRegistry()

    private init() {}

    /// Returns providers for a file, ordered by priority (highest first).
    func providers(
        for file: URL,
        root: URL,
        languageID: String,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> [any LanguageProvider] {
        var providers: [any LanguageProvider] = []

        // Programmatic providers contributed by extensions (out-of-process).
        providers.append(contentsOf: ExtensionProviderManager.shared.providers(
            for: file,
            root: root,
            languageID: languageID,
            openLink: openLink
        ))

        // Language server (lowest priority) — only when a server is configured/running for this language
        // and the language isn't handled by a native engine.
        providers.append(contentsOf: lspProviders(
            for: file,
            root: root,
            languageID: languageID,
            openLink: openLink
        ))

        // Declarative packs are folded into the workspace index and served by the built-in engine.
        if languageID == "php",
           InternalLanguage.isEnabled(.php, in: Settings.shared.preferences.developerSettings) {
            let index = PHPWorkspaceIndex.shared.index(for: root)
            WorkspaceLanguageExtensions.shared.inject(into: index, root: root, language: "php")
            providers.append(PHPWorkspaceIndex.shared.provider(for: file, root: root, openLink: openLink))
        }

        return providers
    }

    /// Providers backed by a running language server for the file's language.
    private func lspProviders(
        for file: URL,
        root: URL,
        languageID: String,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> [any LanguageProvider] {
        MainActor.assumeIsolated { () -> [any LanguageProvider] in
            let lsp = AppServices.lspService
            guard let language = LanguageIdentifier(rawValue: languageID),
                  !lsp.usesInternalLanguage(language),
                  lsp.hasServer(for: language) else {
                return []
            }
            let provider: any LanguageProvider = LSPLanguageProvider(
                languageID: languageID,
                fileURL: file,
                workspacePath: root.absolutePath,
                openLink: openLink
            )
            return [provider]
        }
    }

    /// Re-evaluates language extensions for a workspace after project settings change: removes the
    /// previously injected pack symbols from the index and re-injects with the new activation.
    func reloadExtensions(for root: URL) {
        LanguageExtensionStore.shared.reload()
        ExtensionProviderManager.shared.shutdownAll()
        let index = PHPWorkspaceIndex.shared.index(for: root)
        for url in WorkspaceLanguageExtensions.shared.takeInjectedStubURLs(for: root) {
            index.removeFile(url)
        }
        WorkspaceLanguageExtensions.shared.reload()
        WorkspaceLanguageExtensions.shared.inject(into: index, root: root, language: "php")
    }

    /// Re-evaluates language extensions for all workspaces (after installing, removing, enabling or
    /// disabling a pack from settings).
    func reloadAllExtensions() {
        LanguageExtensionStore.shared.reload()
        ExtensionProviderManager.shared.shutdownAll()

        let roots = PHPWorkspaceIndex.shared.allRoots
        for root in roots {
            let index = PHPWorkspaceIndex.shared.index(for: root)
            for url in WorkspaceLanguageExtensions.shared.takeInjectedStubURLs(for: root) {
                index.removeFile(url)
            }
        }
        WorkspaceLanguageExtensions.shared.reload()
        for root in roots {
            let index = PHPWorkspaceIndex.shared.index(for: root)
            WorkspaceLanguageExtensions.shared.inject(into: index, root: root, language: "php")
        }
    }
}
