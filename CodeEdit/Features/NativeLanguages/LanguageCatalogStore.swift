//
//  LanguageCatalogStore.swift
//  CodeEdit
//
//  Owns the language catalog for one workspace.
//

import Foundation
import CodeEditLang
import CodeEditLanguages
import os

private let catalogStoreLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "",
    category: "LanguageCatalog"
)

/// Owns the language catalog of a single workspace.
///
/// The catalog layers the languages contributed by the workspace's enabled declarative extension
/// packs (installed global packs + the workspace's own `.codeedit/extensions` packs) on top of the
/// built-in languages. Only the packs of *this* workspace are read — a store never scans another
/// workspace, so changing a workspace pack only rebuilds that workspace.
///
/// Rebuilds are driven by ``LanguageExtensionManager/didChangeNotification`` (install, remove,
/// enable, disable) and by explicit ``reload()`` calls when a workspace pack changes on disk.
@MainActor
final class LanguageCatalogStore: ObservableObject {
    /// The workspace whose packs are loaded.
    let workspaceRoot: URL

    /// The catalog contributed languages are layered on.
    private let base: LanguageCatalog

    private let loader = SyntaxContributionLoader()

    /// The current catalog: built-ins plus the enabled contributed languages.
    @Published private(set) var catalog: LanguageCatalog

    /// The number of catalog rebuilds.
    ///
    /// Editor pipelines rebuild on `(version, language fingerprint)`; because a rebuild only
    /// publishes a new version when triggered, an unchanged document keeps its existing pipeline.
    @Published private(set) var version: Int = 0

    /// Per-pack syntax results, including validation errors and warnings, for the Extensions UI.
    @Published private(set) var packOutcomes: [SyntaxContributionLoader.PackOutcome] = []

    private var observer: NSObjectProtocol?

    init(workspaceRoot: URL, base: LanguageCatalog = .builtIn) {
        self.workspaceRoot = workspaceRoot
        self.base = base
        self.catalog = base

        rebuild()

        observer = NotificationCenter.default.addObserver(
            forName: LanguageExtensionManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuild()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Rebuilds the catalog from the workspace's currently enabled packs.
    ///
    /// PERF: this runs synchronously on the main actor and is bounded by the packs and languages in this
    /// workspace. Native grammars are not loaded while building the catalog; validation occurs when the
    /// extension detail is opened, and parsing loads the grammar on first use.
    func rebuild() {
        let packs = enabledPacks()
        let outcomes = SyntaxContributionLoader.resolveConflicts(
            loader.load(
                packs,
                base: base,
                consent: .current,
                nativeGrammarsEnabled: AppServices.settings.preferences.extensions.nativeGrammarsEnabled
            )
        )

        packOutcomes = outcomes
        catalog = SyntaxContributionLoader.catalog(base: base, outcomes: outcomes)
        version &+= 1

        let failures = outcomes.filter { $0.issues.contains { $0.severity == .error } }
        if !failures.isEmpty {
            catalogStoreLogger.error(
                """
                \(failures.count, privacy: .public) language pack(s) have errors in \
                \(self.workspaceRoot.path, privacy: .public).
                """
            )
        }
    }

    /// Re-discovers packs on disk and rebuilds the catalog.
    ///
    /// Enable/disable and install/remove already invalidate the extension store and post
    /// ``LanguageExtensionManager/didChangeNotification``; this is for callers that know a workspace
    /// pack changed on disk.
    func reload() {
        AppServices.languageExtensionStore.reload()
        rebuild()
    }

    /// The languages contributed by the workspace's enabled packs, in load order.
    var contributedLanguages: [ContributedLanguage] {
        packOutcomes.flatMap { outcome in
            outcome.languages.map {
                ContributedLanguage(
                    language: $0,
                    extensionName: outcome.extensionName,
                    extensionVersion: outcome.extensionVersion
                )
            }
        }
    }

    /// The built-in languages the workspace catalog is layered on top of.
    var builtInLanguages: [CodeLanguage] {
        base.languages
    }

    /// A language contributed by an extension syntax pack, with the pack that provided it.
    ///
    /// The inspector lists contributed languages separately from the built-ins and shows the
    /// contributing extension's name and version.
    struct ContributedLanguage: Identifiable {
        let language: CodeLanguage
        let extensionName: String
        let extensionVersion: String?

        var id: String { language.id.rawValue }
    }

    // MARK: - Pack discovery

    /// The workspace's packs that may contribute syntax: global packs first, then workspace packs.
    ///
    /// Activation is deliberately not required. A language has to be visible in detection and the
    /// inspector as soon as its pack is enabled; activation only gates providers and symbols.
    private func enabledPacks() -> [InstalledLanguageExtension] {
        guard AppServices.settings.preferences.extensions.syntaxPacksEnabled else { return [] }
        return AppServices.languageExtensionStore
            .extensions(forWorkspace: workspaceRoot)
            .filter(LanguageExtensionActivation.isEnabled)
    }
}
