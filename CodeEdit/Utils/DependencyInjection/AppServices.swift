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
@MainActor
enum AppServices {
    /// The single, app-wide language server service.
    static let lspService = LSPService()
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
