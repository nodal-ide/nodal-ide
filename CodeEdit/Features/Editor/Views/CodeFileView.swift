//
//  CodeFileView.swift
//  CodeEditModules/CodeFile
//
//  Created by Marco Carnevali on 17/03/22.
//

import Foundation
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages
import CodeEditLang
import CodeEditLangPHP
import Combine

/// CodeFileView is just a wrapper of the `CodeEditor` dependency
struct CodeFileView: View {
    @ObservedObject private var editorInstance: EditorInstance
    @ObservedObject private var codeFile: CodeFileDocument

    @State private var treeSitterClient: TreeSitterClient = TreeSitterClient()

    /// Any coordinators passed to the view.
    private var textViewCoordinators: [TextViewCoordinator]

    /// Highlight providers for this editor.
    ///
    /// The LSP semantic-token provider is only included when a language server actually exists for the file's
    /// language. Otherwise it would request tokens that never arrive and hold highlight ranges pending forever.
    private var highlightProviders: [any HighlightProviding] {
        var providers: [any HighlightProviding] = [treeSitterClient]
        if let lspLanguage = codeFile.getLanguage().lspLanguage,
           !lspService.usesInternalLanguage(lspLanguage),
           lspService.hasServer(for: lspLanguage) {
            providers.insert(codeFile.languageServerObjects.highlightProvider, at: 0)
        }
        return providers
    }

    @AppSettings(\.textEditing.defaultTabWidth)
    var defaultTabWidth
    @AppSettings(\.textEditing.indentOption)
    var indentOption
    @AppSettings(\.textEditing.lineHeightMultiple)
    var lineHeightMultiple
    @AppSettings(\.textEditing.wrapLinesToEditorWidth)
    var wrapLinesToEditorWidth
    @AppSettings(\.textEditing.overscroll)
    var overscroll
    @AppSettings(\.textEditing.showInlayHints)
    var showInlayHints
    @AppSettings(\.textEditing.font)
    var settingsFont
    @AppSettings(\.theme.useThemeBackground)
    var useThemeBackground
    @AppSettings(\.theme.matchAppearance)
    var matchAppearance
    @AppSettings(\.textEditing.letterSpacing)
    var letterSpacing
    @AppSettings(\.textEditing.bracketEmphasis)
    var bracketEmphasis
    @AppSettings(\.textEditing.useSystemCursor)
    var useSystemCursor
    @AppSettings(\.textEditing.showGutter)
    var showGutter
    @AppSettings(\.textEditing.showMinimap)
    var showMinimap
    @AppSettings(\.textEditing.showFoldingRibbon)
    var showFoldingRibbon
    @AppSettings(\.textEditing.reformatAtColumn)
    var reformatAtColumn
    @AppSettings(\.textEditing.showReformattingGuide)
    var showReformattingGuide
    @AppSettings(\.textEditing.invisibleCharacters)
    var invisibleCharactersConfiguration
    @AppSettings(\.textEditing.warningCharacters)
    var warningCharacters

    @Environment(\.colorScheme)
    private var colorScheme

    @EnvironmentObject var undoRegistration: UndoManagerRegistration

    @State private var breakpointLines: Set<Int> = []
    @State private var debugLine: Int?
    @State private var breakpointCancellables = Set<AnyCancellable>()

    @ObservedObject private var themeModel: ThemeModel = .shared

    @State private var treeSitter = TreeSitterClient()

    /// Provides access to the LSP service to decide whether an LSP-backed highlight provider is worthwhile.
    @Service var lspService: LSPService

    private var cancellables = Set<AnyCancellable>()

    private let isEditable: Bool

    /// Whether this view is a lightweight preview (e.g. in the Command Center / Open Quickly), where editor
    /// peripherals like the minimap are unnecessary.
    private let isPreview: Bool

    /// Native language provider for this file, if one exists (currently PHP). Kept for wiring
    /// diagnostics + the debounced index refresh.
    private let nativeProvider: PHPProvider?

    /// The delegate object passed to the editor: either a single provider or an aggregator that
    /// merges several (extensions + built-in engine).
    private let languageDelegate: (any LanguageDelegate)?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        textViewCoordinators: [TextViewCoordinator] = [],
        isEditable: Bool = true,
        isPreview: Bool = false
    ) {
        self._editorInstance = .init(wrappedValue: editorInstance)
        self._codeFile = .init(wrappedValue: codeFile)

        self.textViewCoordinators = textViewCoordinators
            + [editorInstance.rangeTranslator]
            + [codeFile.contentCoordinator]
            + [codeFile.languageServerObjects.textCoordinator]
        self.isEditable = isEditable
        self.isPreview = isPreview

        // Route jump-to-definition through the app, which owns the editor/document model.
        let openLink: (JumpToDefinitionLink) -> Void = { link in
            guard let url = link.url else { return }
            CodeEditDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { document, _, _ in
                (document as? CodeFileDocument)?.openOptions = .init(
                    cursorPositions: [link.targetRange]
                )
            }
        }

        // Build the language-provider pipeline (extensions + built-in engine).
        let pipeline = Self.buildLanguagePipeline(codeFile: codeFile, openLink: openLink)
        self.nativeProvider = pipeline.provider
        self.languageDelegate = pipeline.delegate

        if let openOptions = codeFile.openOptions {
            codeFile.openOptions = nil
            editorInstance.cursorPositions = openOptions.cursorPositions
        }

        codeFile
            .contentCoordinator
            .textUpdatePublisher
            .sink { [weak codeFile] _ in
                codeFile?.updateChangeCount(.changeDone)
            }
            .store(in: &cancellables)

        // Keep the workspace symbol index fresh while editing (debounced).
        if nativeProvider != nil, let fileURL = codeFile.fileURL {
            codeFile
                .contentCoordinator
                .textUpdatePublisher
                .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
                .sink { [weak codeFile] _ in
                    guard let source = codeFile?.content?.string else { return }
                    PHPWorkspaceIndex.shared.refreshFromSource(file: fileURL, source: source)
                }
                .store(in: &cancellables)
        }

        ensureLanguageServerStarted()
    }

    @State private var font: NSFont = Settings[\.textEditing].font.current

    @Environment(\.edgeInsets)
    private var edgeInsets

    var body: some View {
        SourceEditor(
            codeFile.content ?? NSTextStorage(),
            language: codeFile.getLanguage(),
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: currentTheme.editor.editorTheme,
                    useThemeBackground: useThemeBackground,
                    font: font,
                    lineHeightMultiple: lineHeightMultiple,
                    letterSpacing: letterSpacing,
                    wrapLines: wrapLinesToEditorWidth,
                    useSystemCursor: useSystemCursor,
                    tabWidth: defaultTabWidth,
                    bracketPairEmphasis: getBracketPairEmphasis()
                ),
                behavior: .init(
                    isEditable: isEditable,
                    indentOption: indentOption.textViewOption(),
                    reformatAtColumn: reformatAtColumn
                ),
                layout: .init(
                    editorOverscroll: overscroll.overscrollPercentage,
                    contentInsets: edgeInsets.nsEdgeInsets,
                    additionalTextInsets: NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
                ),
                peripherals: .init(
                    showGutter: showGutter,
                    showMinimap: isPreview ? false : showMinimap,
                    showReformattingGuide: showReformattingGuide,
                    showFoldingRibbon: showFoldingRibbon,
                    invisibleCharactersConfiguration: invisibleCharactersConfiguration.textViewOption(),
                    warningCharacters: Set(warningCharacters.characters.keys)
                )
            ),
            state: Binding(
                get: {
                    SourceEditorState(
                        cursorPositions: editorInstance.cursorPositions,
                        scrollPosition: editorInstance.scrollPosition,
                        findText: editorInstance.findText,
                        replaceText: editorInstance.replaceText
                    )
                },
                set: { newState in
                    editorInstance.cursorPositions = newState.cursorPositions ?? []
                    editorInstance.scrollPosition = newState.scrollPosition
                    editorInstance.findText = newState.findText
                    editorInstance.findTextSubject.send(newState.findText)
                    editorInstance.replaceText = newState.replaceText
                    editorInstance.replaceTextSubject.send(newState.replaceText)
                }
            ),
            highlightProviders: highlightProviders,
            undoManager: undoRegistration.manager(forFile: editorInstance.file),
            coordinators: textViewCoordinators,
            completionDelegate: languageDelegate,
            jumpToDefinitionDelegate: languageDelegate,
            hoverDelegate: languageDelegate,
            signatureHelpDelegate: languageDelegate,
            codeActionDelegate: languageDelegate,
            diagnosticsDelegate: languageDelegate,
            symbolsDelegate: languageDelegate,
            inlayHintDelegate: showInlayHints ? languageDelegate : nil,
            foldRangeDelegate: languageDelegate,
            documentHighlightDelegate: languageDelegate,
            breakpointLines: breakpointLines,
            onToggleBreakpoint: { line in
                guard let store = codeFile.findWorkspace()?.breakpointStore, let url = codeFile.fileURL else {
                    return
                }
                store.toggle(url, line: line)
            },
            debugLine: debugLine
        )
        // This view needs to refresh when the codefile changes. The file URL is too stable.
        .id(ObjectIdentifier(codeFile))
        .onAppear(perform: setUpBreakpoints)
        .background {
            if colorScheme == .dark {
                EffectView(.underPageBackground)
            } else {
                EffectView(.contentBackground)
            }
        }
        .colorScheme(currentTheme.appearance == .dark ? .dark : .light)
        // minHeight zero fixes a bug where the app would freeze if the contents of the file are empty.
        .frame(minHeight: .zero, maxHeight: .infinity)
        .onChange(of: settingsFont) { _, newFontSetting in
            font = newFontSetting.current
        }
    }

}

extension CodeFileView {
    /// Builds the language-provider pipeline (extensions + built-in engine) for a file.
    private static func buildLanguagePipeline(
        codeFile: CodeFileDocument,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> (delegate: (any LanguageDelegate)?, provider: PHPProvider?) {
        var providers: [any LanguageProvider] = []
        if let workspaceRoot = codeFile.findWorkspace()?.fileURL, let fileURL = codeFile.fileURL {
            providers = LanguageProviderRegistry.shared.providers(
                for: fileURL,
                root: workspaceRoot,
                languageID: codeFile.getLanguage().id.rawValue,
                openLink: openLink
            )
        }

        let phpProvider = providers.compactMap { $0 as? PHPProvider }.first
        phpProvider?.diagnosticsConfig = Self.phpDiagnosticsConfig()
        phpProvider?.onDiagnostics = { url, diagnostics in
            DiagnosticsStore.shared.update(file: url, diagnostics: diagnostics)
        }

        let delegate: (any LanguageDelegate)?
        switch providers.count {
        case 0: delegate = nil
        case 1: delegate = providers[0]
        default: delegate = LanguageProviderAggregator(providers: providers)
        }
        return (delegate, phpProvider)
    }

    /// Ensures the language server starts for this document. Documents restored at launch may open before the
    /// workspace/configs are ready, so the `didOpen` notification alone can miss them.
    private func ensureLanguageServerStarted() {
        guard codeFile.getLanguage().lspLanguage != nil,
              let lsp = ServiceContainer.resolve(.singleton, LSPService.self) else {
            return
        }
        lsp.openDocument(codeFile)
    }

    /// Maps the app's PHP diagnostics settings to the engine's configuration.
    private static func phpDiagnosticsConfig() -> PHPDiagnosticsConfig {
        let settings = Settings.shared.preferences.phpDiagnostics
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

    /// Seeds the gutter breakpoint markers and debug line, keeping them in sync with the workspace.
    private func setUpBreakpoints() {
        guard let workspace = codeFile.findWorkspace() else { return }
        if let store = workspace.breakpointStore, let url = codeFile.fileURL {
            breakpointLines = store.lines(for: url)
            store.$breakpoints
                .receive(on: RunLoop.main)
                .sink { _ in
                    breakpointLines = store.lines(for: url)
                }
                .store(in: &breakpointCancellables)
        }
        if let session = workspace.debugController?.session {
            updateDebugLine(session)
            session.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak session] _ in
                    DispatchQueue.main.async {
                        if let session { updateDebugLine(session) }
                    }
                }
                .store(in: &breakpointCancellables)
        }
    }

    /// Highlights the current debug stop line when it's in this file.
    private func updateDebugLine(_ session: DebugSession) {
        guard session.state.isStopped,
              let frame = session.currentFrame,
              let path = frame.source?.path,
              path == codeFile.fileURL?.path(percentEncoded: false) else {
            debugLine = nil
            return
        }
        debugLine = frame.line
    }

    private var currentTheme: Theme {
        themeModel.selectedTheme ?? themeModel.themes.first!
    }

    /// Determines the style of bracket emphasis based on the `bracketEmphasis` setting and the current theme.
    /// - Returns: The emphasis style to use for bracket pair emphasis.
    private func getBracketPairEmphasis() -> BracketPairEmphasis? {
        let color = if Settings[\.textEditing].bracketEmphasis.useCustomColor {
            Settings[\.textEditing].bracketEmphasis.color.nsColor
        } else {
            currentTheme.editor.text.nsColor.withAlphaComponent(0.8)
        }

        switch Settings[\.textEditing].bracketEmphasis.highlightType {
        case .disabled:
            return nil
        case .flash:
            return .flash
        case .bordered:
            return .bordered(color: color)
        case .underline:
            return .underline(color: color)
        }
    }
}
