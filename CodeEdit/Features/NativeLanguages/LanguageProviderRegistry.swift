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
@MainActor
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
        providers.append(contentsOf: AppServices.extensionProviderManager.providers(
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
        // The engine that hosts the index is resolved from the internal-language registry rather than
        // a hard-coded language id, so extension syntax packs for other languages are unaffected.
        if let identifier = LanguageIdentifier(rawValue: languageID),
           let engine = InternalLanguage.implementing(identifier),
           engine.supportsDeclarativeSymbolInjection,
           InternalLanguage.isEnabled(identifier, in: AppServices.settings.preferences.developerSettings) {
            let index = AppServices.phpWorkspaceIndex.index(for: root)
            AppServices.workspaceLanguageExtensions.inject(into: index, root: root, language: engine.rawValue)
            providers.append(AppServices.phpWorkspaceIndex.provider(for: file, root: root, openLink: openLink))
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

    /// Re-evaluates language extensions for a workspace after project settings change: removes the
    /// previously injected pack symbols from the index and re-injects with the new activation.
    func reloadExtensions(for root: URL) {
        AppServices.languageExtensionStore.reload()
        AppServices.extensionProviderManager.shutdownAll()
        let index = AppServices.phpWorkspaceIndex.index(for: root)
        for url in AppServices.workspaceLanguageExtensions.takeInjectedStubURLs(for: root) {
            index.removeFile(url)
        }
        AppServices.workspaceLanguageExtensions.reload()
        AppServices.workspaceLanguageExtensions.inject(into: index, root: root, language: "php")
    }

    /// Re-evaluates language extensions for all workspaces (after installing, removing, enabling or
    /// disabling a pack from settings).
    func reloadAllExtensions() {
        AppServices.languageExtensionStore.reload()
        AppServices.extensionProviderManager.shutdownAll()

        let roots = AppServices.phpWorkspaceIndex.allRoots
        for root in roots {
            let index = AppServices.phpWorkspaceIndex.index(for: root)
            for url in AppServices.workspaceLanguageExtensions.takeInjectedStubURLs(for: root) {
                index.removeFile(url)
            }
        }
        AppServices.workspaceLanguageExtensions.reload()
        for root in roots {
            let index = AppServices.phpWorkspaceIndex.index(for: root)
            AppServices.workspaceLanguageExtensions.inject(into: index, root: root, language: "php")
        }
    }
}
