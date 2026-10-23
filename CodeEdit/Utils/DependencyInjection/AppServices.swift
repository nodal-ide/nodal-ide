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
    @MainActor static var commandCenterRegistry: CommandCenterRegistry = .shared

    /// The app-wide runtime manager.
    @MainActor static var runtimeManager: RuntimeManager = .shared

    /// The app-wide local proxy service (single-instance lock, domain registry, nginx/certs later).
    @MainActor static var localProxy: LocalProxyService = .shared

    /// The app-wide resolved runtime environment.
    @MainActor static var runtimeEnvironment: RuntimeEnvironment = .shared

    // MARK: Native language services

    /// The app-wide PHP workspace symbol index.
    static var phpWorkspaceIndex: PHPWorkspaceIndex = .shared

    /// The app-wide problems/diagnostics store.
    @MainActor static var diagnosticsStore: DiagnosticsStore = .shared

    /// The app-wide store of installed language extensions.
    static var languageExtensionStore: LanguageExtensionStore = .shared

    /// The app-wide configured extension sources.
    @MainActor static var extensionSourceStore = ExtensionSourceStore.shared

    /// The app-wide marketplace catalog cache/service.
    static let extensionCatalogService = ExtensionCatalogService()

    /// The app-wide extension registry authoring/publishing service.
    static let extensionRegistryService = ExtensionRegistryService()

    /// The app-wide registry of marketplace source transport providers.
    ///
    /// Providers are host-owned implementations; marketplace source records select among these
    /// identifiers. Tests may substitute a different registry.
    @MainActor static var extensionSourceProviders: ExtensionSourceProviderRegistry? =
        makeExtensionSourceProviders()

    private static func makeExtensionSourceProviders() -> ExtensionSourceProviderRegistry? {
        do {
            return try ExtensionSourceProviderRegistry(providers: [
                HTTPSStaticIndexProvider(),
                GitRepositoryProvider()
            ])
        } catch {
            assertionFailure("Duplicate marketplace source provider identifier: \(error)")
            return nil
        }
    }

    /// The app-wide per-workspace language-extension injection registry.
    static var workspaceLanguageExtensions: WorkspaceLanguageExtensions = .shared

    /// The app-wide native language provider registry.
    @MainActor static var languageProviderRegistry: LanguageProviderRegistry = .shared

    /// The app-wide out-of-process extension provider manager.
    static var extensionProviderManager: ExtensionProviderManager = .shared

    /// The app-wide project-scan progress tracker.
    @MainActor static var projectScanStatus: ProjectScanStatus = .shared

    // MARK: Source control viewers

    /// The app-wide diff viewer state.
    @MainActor static var diffViewerState: DiffViewerState = .shared

    /// The app-wide diff viewer presenter.
    @MainActor static var diffViewerPresenter: DiffViewerPresenter = .shared

    /// The app-wide blame viewer state.
    @MainActor static var blameViewerState: BlameViewerState = .shared

    /// The app-wide blame viewer presenter.
    @MainActor static var blameViewerPresenter: BlameViewerPresenter = .shared

    /// The app-wide merge-conflict resolver state.
    @MainActor static var conflictResolverState: ConflictResolverState = .shared

    /// The app-wide merge-conflict resolver presenter.
    @MainActor static var conflictResolverPresenter: ConflictResolverPresenter = .shared

    // MARK: Knowledge

    /// The app-wide documentation-set registry.
    static var knowledgeRegistry: KnowledgeRegistry = .shared

    /// The app-wide knowledge search index.
    static var knowledgeSearchIndex: KnowledgeSearchIndex = .shared

    /// The app-wide knowledge navigation router.
    static var knowledgeRouter: KnowledgeRouter = .shared

    // MARK: Extensions

    /// The app-wide extension manager.
    static var extensionManager: ExtensionManager = .shared

    /// The app-wide extension discovery service.
    static var extensionDiscovery: ExtensionDiscovery = .shared

    /// The app-wide language-extension manager.
    @MainActor static var languageExtensionManager: LanguageExtensionManager = .shared

    // MARK: Misc

    /// The app-wide LSP server registry manager.
    @MainActor static var registryManager: RegistryManager = .shared

    /// The app-wide feedback model.
    static var feedbackModel: FeedbackModel = .shared

    /// The app-wide search-settings model.
    static var searchSettingsModel: SearchSettingsModel = .shared

    /// The app-wide problems-results cache.
    @MainActor static var problemsResultsCache: ProblemsResultsCache = .shared

    /// The app-wide internal-development output source.
    static var internalDevelopmentOutputSource: InternalDevelopmentOutputSource = .shared

    /// The app-wide LSP diagnostics cache.
    @MainActor static var lspDiagnosticsCache: LSPDiagnosticsCache = .shared

    /// The app-wide editor state restoration store.
    static var editorStateRestoration: EditorStateRestoration? = .shared

    /// The app-wide cache of terminal views (kept alive while off-screen).
    static var terminalCache: TerminalCache = .shared

    // MARK: Debug

    /// The app-wide Xdebug detector.
    @MainActor static var xdebugDetector: XdebugDetector = .shared

    /// The app-wide PHP debug-adapter installer.
    @MainActor static var phpAdapterInstaller: PHPAdapterInstaller = .shared

    // MARK: Documents

    /// The app-wide close-confirmation responder target.
    static var closeConfirmationTarget: CloseConfirmationTarget = .shared
}

// MARK: - Environment injection

private struct LSPServiceEnvironmentKey: EnvironmentKey {
    static var defaultValue: LSPService {
        // `EnvironmentKey.defaultValue` is nonisolated, but SwiftUI reads it on the main actor when a
        // view is created. `LSPService` is main-actor isolated, so bridge the isolation here.
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
