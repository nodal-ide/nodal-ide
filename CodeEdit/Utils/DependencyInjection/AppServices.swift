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
