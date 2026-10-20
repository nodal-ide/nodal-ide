//
//  LanguageExtensionManager.swift
//  CodeEdit
//
//  Observable list of installed declarative language extensions (packs) for the Extensions window.
//

import SwiftUI

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
        reloadAll()
    }
}
