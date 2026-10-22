//
//  LanguageExtensionManager.swift
//  CodeEdit
//
//  Observable list of installed declarative language extensions (packs) for the Extensions window.
//

import SwiftUI
import CodeEditLang
import CodeEditLanguages

/// Manages the installed language extensions shown in the Extensions window and settings.
@MainActor
final class LanguageExtensionManager: ObservableObject {
    static let shared = LanguageExtensionManager()
    static let didChangeNotification = Notification.Name("CodeEdit.LanguageExtensionsDidChange")

    /// Globally installed packs (Application Support/CodeEdit/Extensions).
    @Published var extensions: [InstalledLanguageExtension] = []

    private init() {
        reload()
    }

    /// Re-reads the installed packs from disk.
    func reload() {
        extensions = AppServices.languageExtensionStore.globalExtensions()
    }

    /// Reloads packs and re-applies them to all open workspaces.
    func reloadAll() {
        NativeGrammarLoader.shared.resetFailures()
        AppServices.languageExtensionStore.reload()
        AppServices.languageProviderRegistry.reloadAllExtensions()
        AppServices.knowledgeSearchIndex.invalidate()
        AppServices.knowledgeRegistry.reload()
        reload()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func install(fromFolder folder: URL) throws {
        try AppServices.languageExtensionStore.install(fromFolder: folder)
        reloadAll()
    }

    func install(fromZip zipURL: URL) throws {
        try AppServices.languageExtensionStore.install(fromZip: zipURL)
        reloadAll()
    }

    func remove(_ ext: InstalledLanguageExtension) throws {
        try AppServices.languageExtensionStore.remove(ext)
        AppServices.settings.preferences.extensions.disabledExtensions.removeAll { $0 == ext.id }
        revokeNativeGrammarConsent(packID: ext.id)
        reloadAll()
    }

    /// Captures the consent state before a marketplace replacement so it can be reconciled against
    /// the new package without granting consent for bytes the user has never approved.
    var nativeGrammarConsentSnapshot: [String: String] {
        AppServices.settings.preferences.extensions.nativeGrammarConsent
    }

    /// Applies runtime changes after a marketplace package has been installed transactionally.
    ///
    /// Disabled state is keyed by extension ID and therefore survives a replacement. Native grammar
    /// consent is preserved only for declarations whose bytes are unchanged; changed or new grammars
    /// require a fresh trust decision.
    func completeMarketplaceInstall(
        _ ext: InstalledLanguageExtension,
        consentBefore: [String: String]
    ) {
        AppServices.settings.preferences.extensions.nativeGrammarConsent =
            NativeGrammarConsentReconciler.reconciled(
                existing: consentBefore,
                packID: ext.id,
                installed: ext
            )
        reloadAll()
    }

    // MARK: - Native grammar trust

    /// The native grammars the user has explicitly trusted.
    var nativeGrammarConsent: NativeGrammarConsent { .current }

    /// Records consent for every native grammar `ext` ships, hashing the bytes on disk as they are now.
    ///
    /// - Returns: The grammar paths that were approved. Empty when the pack ships native grammars that
    ///   could not be read, in which case nothing is recorded.
    @discardableResult
    func trustNativeGrammars(of ext: InstalledLanguageExtension) -> [String] {
        var recorded = AppServices.settings.preferences.extensions.nativeGrammarConsent
        var approved: [String] = []

        for declaration in NativeGrammarConsent.declarations(in: ext) {
            guard let url = LanguageExtensionPaths.resolve(declaration.path, in: ext.root),
                  LanguageExtensionPaths.isContained(url, in: ext.root),
                  let hash = NativeGrammarConsent.hashOfFile(at: url) else { continue }
            recorded[NativeGrammarConsent.key(packID: ext.id, grammarPath: declaration.path)] = hash
            approved.append(declaration.path)
        }

        guard !approved.isEmpty else { return [] }
        AppServices.settings.preferences.extensions.nativeGrammarConsent = recorded
        // A grammar that failed before (for example after being replaced) may load now.
        NativeGrammarLoader.shared.resetFailures()
        reloadAll()
        return approved
    }

    /// Drops the consent recorded for `ext`'s native grammars.
    func revokeNativeGrammars(of ext: InstalledLanguageExtension) {
        revokeNativeGrammarConsent(packID: ext.id)
        reloadAll()
    }

    private func revokeNativeGrammarConsent(packID: String) {
        let prefix = "\(packID)/"
        let remaining = AppServices.settings.preferences.extensions.nativeGrammarConsent
            .filter { !$0.key.hasPrefix(prefix) }
        AppServices.settings.preferences.extensions.nativeGrammarConsent = remaining
    }
}
