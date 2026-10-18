//
//  AppServices.swift
//  CodeEdit
//

import SwiftUI

/// Application-wide services that outlive any single workspace or window.
///
/// This is the app-scope counterpart to ``WorkspaceServices``: only services that are genuinely global to
/// the running application belong here. It replaces the previous type-erased `ServiceContainer` registry,
/// which existed only to hold the single app-wide ``LSPService``.
enum AppServices {
    /// The single, app-wide language server service.
    @MainActor static let lspService = LSPService()

    /// The app-wide settings store.
    ///
    /// This is the single injection point for preferences: everything (views via ``AppSettings``, and
    /// non-view code) reads and writes through it, so tests/previews can substitute their own store.
    static var settings: any SettingsProviding = Settings.shared

    /// The app-wide notification manager (in-app banners + system notifications).
    static var notificationManager: NotificationManager = .shared

    /// The app-wide theme model.
    static var themeModel: ThemeModel = .shared

    /// The app-wide command registry.
    static var commandManager: CommandManager = .shared

    /// The app-wide keybinding manager.
    static var keybindingManager: KeybindingManager = .shared

    /// The app-wide command-center provider registry.
    static var commandCenterRegistry: CommandCenterRegistry = .shared

    /// The app-wide runtime manager.
    @MainActor static var runtimeManager: RuntimeManager = .shared

    /// The app-wide resolved runtime environment.
    @MainActor static var runtimeEnvironment: RuntimeEnvironment = .shared

    // MARK: Native language services

    /// The app-wide PHP workspace symbol index.
    static var phpWorkspaceIndex: PHPWorkspaceIndex = .shared

    /// The app-wide problems/diagnostics store.
    @MainActor static var diagnosticsStore: DiagnosticsStore = .shared

    /// The app-wide store of installed language extensions.
    static var languageExtensionStore: LanguageExtensionStore = .shared

    /// The app-wide per-workspace language-extension injection registry.
    static var workspaceLanguageExtensions: WorkspaceLanguageExtensions = .shared

    /// The app-wide native language provider registry.
    static var languageProviderRegistry: LanguageProviderRegistry = .shared

    /// The app-wide out-of-process extension provider manager.
    static var extensionProviderManager: ExtensionProviderManager = .shared

    /// The app-wide project-scan progress tracker.
    @MainActor static var projectScanStatus: ProjectScanStatus = .shared
}

// MARK: - Environment injection

private struct LSPServiceEnvironmentKey: EnvironmentKey {
    static var defaultValue: LSPService {
        MainActor.assumeIsolated { AppServices.lspService }
    }
}

extension EnvironmentValues {
    /// The app-wide ``LSPService``, injectable so views (and tests) can supply a different instance.
    var lspService: LSPService {
        get { self[LSPServiceEnvironmentKey.self] }
        set { self[LSPServiceEnvironmentKey.self] = newValue }
    }
}
