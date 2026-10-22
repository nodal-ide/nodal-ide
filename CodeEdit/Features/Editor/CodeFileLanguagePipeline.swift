//
//  CodeFileLanguagePipeline.swift
//  CodeEdit
//
//  Builds the per-document language-provider pipeline (registered extensions + the built-in engine)
//  and maps the app's PHP diagnostics settings to the engine configuration. Extracted from
//  `CodeFileView` so the view is not responsible for provider wiring.
//

import Foundation
import CodeEditSourceEditor
import CodeEditLang
import CodeEditLangPHP

@MainActor
enum CodeFileLanguagePipeline {
    struct Result {
        let delegate: (any LanguageDelegate)?
        let provider: PHPProvider?
    }

    static func build(
        for codeFile: CodeFileDocument,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> Result {
        var providers: [any LanguageProvider] = []
        let language = codeFile.getLanguage(catalog: codeFile.workspaceLanguageCatalog())
        if let workspaceRoot = codeFile.findWorkspace()?.fileURL, let fileURL = codeFile.fileURL {
            providers = AppServices.languageProviderRegistry.providers(
                for: fileURL,
                root: workspaceRoot,
                languageID: language.id.rawValue,
                openLink: openLink
            )
        }

        let phpProvider = providers.compactMap { $0 as? PHPProvider }.first
        phpProvider?.diagnosticsConfig = diagnosticsConfig()
        phpProvider?.onDiagnostics = { url, diagnostics in
            AppServices.diagnosticsStore.update(file: url, diagnostics: diagnostics)
        }

        let delegate: (any LanguageDelegate)?
        switch providers.count {
        case 0: delegate = nil
        case 1: delegate = providers[0]
        default: delegate = LanguageProviderAggregator(providers: providers)
        }
        return Result(delegate: delegate, provider: phpProvider)
    }

    /// Maps the app's PHP diagnostics settings to the engine's configuration.
    static func diagnosticsConfig() -> PHPDiagnosticsConfig {
        let settings = AppServices.settings.preferences.phpDiagnostics
        var config = PHPDiagnosticsConfig()
        config.classLength = settings.classLength
        config.methodLength = settings.methodLength
        config.fileLength = settings.fileLength
        config.parameterCount = settings.parameterCount
        config.complexity = settings.complexity
        config.lineLength = settings.lineLength
        config.requireStrictTypes = settings.requireStrictTypes
        config.reportTodos = settings.reportTodos
        config.reportNaming = settings.reportNaming
        config.disabledRules = Set(settings.disabledRules)
        config.skipPatterns = settings.skipPatterns
        return config
    }
}
