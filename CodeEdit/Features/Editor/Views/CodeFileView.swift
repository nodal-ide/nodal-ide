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
    let editorInstance: EditorInstance
    @ObservedObject var codeFile: CodeFileDocument

    /// The workspace language catalog (built-ins + enabled extension syntax packs) used for detection
    /// and syntax highlighting. Resolved once when the view is created.
    private let catalog: LanguageCatalog

    @State private var treeSitterClient: TreeSitterClient

    /// Any coordinators passed to the view.
    private var textViewCoordinators: [TextViewCoordinator]

    /// Highlight providers for this editor.
    ///
    /// The LSP semantic-token provider is only included when a language server actually exists for the file's
    /// language. Otherwise it would request tokens that never arrive and hold highlight ranges pending forever.
    private var highlightProviders: [any HighlightProviding] {
        var providers: [any HighlightProviding] = [treeSitterClient]
        if let lspLanguage = codeFile.getLanguage(catalog: catalog).lspLanguage,
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

    @State var breakpointRevision = 0
    @State var debugRevision = 0
    @State var findRevision = 0
    @State var breakpointObservers = Set<AnyCancellable>()

    @ObservedObject var themeModel: ThemeModel = AppServices.themeModel

    /// Provides access to the LSP service to decide whether an LSP-backed highlight provider is worthwhile.
    @Environment(\.lspService)
    private var lspService

    /// Owns the document-change tracking, symbol-index refresh, and language-server start (stable lifetime).
    @StateObject private var lifecycle = CodeFileLifecycleCoordinator()

    let isEditable: Bool

    /// Whether this view is a lightweight preview (e.g. in the Command Center / Open Quickly), where
    /// heavyweight editor peripherals are unnecessary.
    let isPreview: Bool

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
        self.editorInstance = editorInstance
        self._codeFile = .init(wrappedValue: codeFile)

        // Contributed languages resolve their grammar and queries through the workspace catalog, so the
        // syntax highlighter must be created with it rather than the built-in default.
        let catalog = codeFile.workspaceLanguageCatalog()
        self.catalog = catalog
        self._treeSitterClient = State(wrappedValue: TreeSitterClient(catalog: catalog))

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
        let pipeline = CodeFileLanguagePipeline.build(for: codeFile, openLink: openLink)
        self.nativeProvider = pipeline.provider
        self.languageDelegate = pipeline.delegate

        if let openOptions = codeFile.openOptions {
            codeFile.openOptions = nil
            editorInstance.cursorPositions = openOptions.cursorPositions
        }
    }

    @State var font: NSFont = AppServices.settings[\.textEditing].font.current

    @Environment(\.edgeInsets)
    var edgeInsets

    var body: some View {
        SourceEditor(
            codeFile.content ?? NSTextStorage(),
            language: codeFile.getLanguage(catalog: catalog),
            configuration: editorConfiguration,
            state: editorStateBinding,
            highlightProviders: highlightProviders,
            catalog: catalog,
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
            breakpointLines: currentBreakpointLines,
            disabledBreakpointLines: currentDisabledBreakpointLines,
            onToggleBreakpoint: toggleBreakpoint(line:),
            onBreakpointMenu: breakpointMenu(line:),
            debugLine: currentDebugLine
        )
        // This view needs to refresh when the codefile changes. The file URL is too stable.
        .id(ObjectIdentifier(codeFile))
        // Subscribe once; the values are recomputed from the current file each render.
        .onAppear {
            observeEditorState()
            lifecycle.start(codeFile: codeFile, refreshSymbolIndex: nativeProvider != nil)
            lifecycle.ensureLanguageServerStarted(codeFile: codeFile)
        }
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
