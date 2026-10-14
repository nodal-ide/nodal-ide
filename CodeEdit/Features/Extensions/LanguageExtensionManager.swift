//
//  LanguageExtensionManager.swift
//  CodeEdit
//
//  Observable list of installed declarative language extensions (packs) for the Extensions window.
//

import SwiftUI

/// Manages the installed language extensions shown in the Extensions window and settings.
final class LanguageExtensionManager: ObservableObject {
    static let shared = LanguageExtensionManager()

    /// Globally installed packs (Application Support/CodeEdit/Extensions).
    @Published var extensions: [InstalledLanguageExtension] = []

    private init() {
        reload()
    }

    /// Re-reads the installed packs from disk.
    func reload() {
        extensions = LanguageExtensionStore.shared.globalExtensions()
    }

    /// Reloads packs and re-applies them to all open workspaces.
    func reloadAll() {
        LanguageExtensionStore.shared.reload()
        LanguageProviderRegistry.shared.reloadAllExtensions()
        reload()
    }

    func install(fromFolder folder: URL) throws {
        try LanguageExtensionStore.shared.install(fromFolder: folder)
        reloadAll()
    }

    func install(fromZip zipURL: URL) throws {
        try LanguageExtensionStore.shared.install(fromZip: zipURL)
        reloadAll()
    }

    func remove(_ ext: InstalledLanguageExtension) throws {
        try LanguageExtensionStore.shared.remove(ext)
        Settings.shared.preferences.extensions.disabledExtensions.removeAll { $0 == ext.id }
        reloadAll()
    }
}
