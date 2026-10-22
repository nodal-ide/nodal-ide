//
//  ExtensionProviderManager.swift
//  CodeEdit
//
//  Creates and caches out-of-process language providers contributed by extensions.
//

import Foundation
import CodeEditSourceEditor
import CodeEditLang
import CodeEditLangPHP

/// Owns the `StdioLanguageServer` processes contributed by language-extension providers.
///
/// One process is started per (extension, workspace) and shared across files; a fresh
/// `ExtensionLanguageProvider` is created per open file.
final class ExtensionProviderManager {
    static let shared = ExtensionProviderManager()

    private let lock = NSLock()
    private var servers: [String: StdioLanguageServer] = [:]

    private init() {}

    /// Creates one provider per enabled extension. Each provider advertises its supported zones;
    /// the aggregator routes requests without duplicating extension processes or provider objects.
    @MainActor
    func providers(
        for file: URL,
        root: URL,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> [any LanguageProvider] {
        var result: [any LanguageProvider] = []

        for ext in AppServices.languageExtensionStore.extensions(forWorkspace: root) {
            guard let contribution = ext.manifest.contributes?.provider else { continue }
            let languages = contribution.languages ?? ext.manifest.languages ?? []
            guard LanguageExtensionActivation.isEnabled(ext),
                  LanguageExtensionActivation.isActivated(ext, in: root),
                  !languages.isEmpty else {
                continue
            }

            let server = server(for: ext, contribution: contribution, root: root)
            result.append(
                ExtensionLanguageProvider(
                    languageIDs: Set(languages),
                    fileURL: file,
                    server: server,
                    openLink: openLink
                )
            )
        }

        return result
    }

    /// Stops all provider processes (call after extensions are reloaded).
    func shutdownAll() {
        lock.lock()
        let running = Array(servers.values)
        servers.removeAll()
        lock.unlock()
        running.forEach { $0.stop() }
    }

    private func server(
        for ext: InstalledLanguageExtension,
        contribution: LanguageExtensionManifest.Contributes.Provider,
        root: URL
    ) -> StdioLanguageServer {
        let key = "\(ext.id)|\(root.path(percentEncoded: false))"

        lock.lock()
        if let existing = servers[key] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let server = StdioLanguageServer(
            command: contribution.command,
            args: contribution.args ?? [],
            environment: contribution.env,
            workingDirectory: ext.root
        )

        lock.lock()
        servers[key] = server
        lock.unlock()
        return server
    }
}
