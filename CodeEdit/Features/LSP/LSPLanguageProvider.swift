//
//  LSPLanguageProvider.swift
//  CodeEdit
//
//  A `LanguageProvider` backed by a running language server (LSP). Registered at the lowest
//  priority so extensions and the built-in engine take precedence when they have results.
//

import Foundation
import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLang
import CodeEditLangPHP
import LanguageServerProtocol

/// A completion entry produced by a language server.
struct LSPCompletionEntry: CodeSuggestionEntry {
    let label: String
    let detail: String?
    let documentation: String?
    let insertText: String

    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var image: Image { Image(systemName: "text.alignleft") }
    var imageColor: SwiftUI.Color { SwiftUI.Color(NSColor.systemTeal) }
    var deprecated: Bool { false }
}

/// A language provider backed by an LSP server.
@MainActor
final class LSPLanguageProvider: LanguageProvider {
    let languageID: String
    let priority: LanguageProviderPriority = .lsp

    private let fileURL: URL
    let workspacePath: String
    private let openLinkHandler: (JumpToDefinitionLink) -> Void

    /// The running server for this file's language, resolved lazily (it may still be starting when the
    /// file is opened).
    var server: LanguageServer<CodeFileDocument>? {
        guard let language = LanguageIdentifier(rawValue: languageID) else {
            return nil
        }
        return AppServices.lspService.languageClient(for: language, workspacePath: workspacePath)
    }

    /// The last completion request: the LSP position and the items it returned.
    var completionPosition: Position?
    var completionItems: [CompletionItem] = []

    var documentURI: String { fileURL.lspURI }

    var sourceTextProvider: any SourceTextProviding = DiskSourceTextProvider()

    nonisolated var supportsReferences: Bool { true }

    init(
        languageID: String,
        fileURL: URL,
        workspacePath: String,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) {
        self.languageID = languageID
        self.fileURL = fileURL
        self.workspacePath = workspacePath
        self.openLinkHandler = openLink
    }

    // MARK: - JumpToDefinition

    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        guard let server = server,

              let position = textView.textView.lspRangeFrom(nsRange: range)?.start else { return nil }
        guard let response = try? await server.requestGoToDefinition(for: documentURI, position: position) else {
            return nil
        }

        let locations: [Location]
        switch response {
        case .optionA(let location):
            locations = [location]
        case .optionB(let list):
            locations = list
        case .optionC(let links):
            locations = links.map { Location(uri: $0.targetUri, range: $0.targetRange) }
        }
        guard !locations.isEmpty else { return nil }

        return locations.map { location in
            let url = URL(string: location.uri)
            return JumpToDefinitionLink(
                url: url == fileURL ? nil : url,
                targetRange: CursorPosition(
                    line: location.range.start.line + 1,
                    column: location.range.start.character + 1
                ),
                typeName: url?.lastPathComponent ?? "",
                sourcePreview: location.uri,
                documentation: nil,
                image: Image(systemName: "arrow.turn.down.right"),
                imageColor: SwiftUI.Color(NSColor.systemTeal)
            )
        }
    }

    func openLink(link: JumpToDefinitionLink) {
        openLinkHandler(link)
    }

    // MARK: - Hover

    @MainActor
    func hoverInfo(forRange range: NSRange, textView: TextViewController) async -> HoverInfo? {
        guard let server = server,

              let position = textView.textView.lspRangeFrom(nsRange: range)?.start else { return nil }
        guard let hover = try? await server.requestHover(for: documentURI, position),
              let content = LSPHoverMapper.content(hover.contents) else { return nil }
        return HoverInfo(contents: content.plainText, range: range)
    }

    // MARK: - References

    func references(for query: ReferenceQuery) async -> ReferenceQueryOutcome {
        guard let server else {
            return .failed(.notReady("The \(languageID) language server is still starting."))
        }
        guard server.serverCapabilities.referencesProvider != nil else {
            return .unsupported(reason: "The \(languageID) language server doesn't support find references.")
        }
        guard let position = ReferenceLocationMapper.position(
            forOffset: query.target.range.location,
            in: query.source
        ) else {
            return .unsupported(reason: "Place the cursor on a symbol to find its references.")
        }

        let locations: [Location]
        do {
            locations = try await server.requestFindReferences(
                for: query.target.fileURL.lspURI,
                Position(line: position.line, character: position.character),
                query.includeDeclaration
            ) ?? []
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch {
            return .failed(.transport(error.localizedDescription))
        }

        let refs = locations.map {
            ReferenceLocationMapper.LocationRef(
                uri: $0.uri,
                startLine: $0.range.start.line,
                startCharacter: $0.range.start.character,
                endLine: $0.range.end.line,
                endCharacter: $0.range.end.character
            )
        }
        let textProvider = sourceTextProvider
        let limit = query.maxResults
        return await Task.detached(priority: .userInitiated) {
            ReferenceLocationMapper.outcome(for: refs, textProvider: textProvider, limit: limit)
        }.value
    }

    // MARK: - Diagnostics

    @MainActor
    func diagnostics(for textView: TextViewController) async -> [EditorDiagnostic] {
        // We don't declare pull-diagnostics support, and servers that push (TypeScript, CSS, …) may still
        // advertise `diagnosticProvider` while not implementing `textDocument/diagnostic`. Use the latest
        // pushed diagnostics for this document instead of pulling.
        AppServices.lspDiagnosticsCache.diagnostics(for: documentURI).compactMap {
            editorDiagnostic(from: $0, in: textView)
        }
    }

    private func editorDiagnostic(from diagnostic: Diagnostic, in textView: TextViewController) -> EditorDiagnostic? {
        guard let range = textView.textView.nsRange(fromLSP: diagnostic.range) else { return nil }
        return EditorDiagnostic(
            range: range,
            severity: Self.severity(diagnostic.severity),
            message: diagnostic.message,
            line: diagnostic.range.start.line + 1
        )
    }

    // MARK: - Code actions

    @MainActor
    func codeActions(forRange range: NSRange, textView: TextViewController) async -> [CodeActionInfo] {
        guard let server = server,
              let lspRange = textView.textView.lspRangeFrom(nsRange: range) else {
            return []
        }
        let diagnostics = AppServices.lspDiagnosticsCache.diagnostics(for: documentURI)
        let context = CodeActionContext(diagnostics: diagnostics, only: nil)
        guard let response = try? await server.requestCodeActions(
            for: documentURI,
            range: lspRange,
            context: context
        ) else {
            return []
        }

        var actions: [CodeActionInfo] = []
        for option in response ?? [] {
            guard case .optionB(var action) = option else { continue }
            if action.edit == nil, action.data != nil,
               let resolved = try? await server.requestCodeActionResolve(action) {
                action = resolved
            }
            guard let edit = action.edit else { continue }
            let edits = codeActionEdits(edit, in: textView.textView)
            guard !edits.isEmpty else { continue }
            actions.append(CodeActionInfo(title: action.title, kind: action.kind, edits: edits))
        }
        return actions
    }

    /// Extracts text edits that apply to the open document (cross-file edits are not shown here).
    private func codeActionEdits(_ edit: WorkspaceEdit, in textView: TextView) -> [CodeActionEdit] {
        guard let textEdits = edit.changes?[documentURI] else { return [] }
        return textEdits.compactMap { textEdit in
            guard let range = textView.nsRange(fromLSP: textEdit.range) else { return nil }
            return CodeActionEdit(range: range, text: textEdit.newText)
        }
    }

    // MARK: - Completion

    @MainActor
    func completionTriggerCharacters() -> Set<String> {
        Set(server?.serverCapabilities.completionProvider?.triggerCharacters ?? [])
    }

    @MainActor
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard let startPosition = completionPosition, !completionItems.isEmpty else { return nil }
        let prefixStart = textView.textView.offset(forLSPPosition: startPosition) ?? 0
        let cursor = cursorPosition.range.location
        let nsString = textView.textView.string as NSString
        let clampedStart = min(max(prefixStart, 0), nsString.length)
        let clampedEnd = min(max(cursor, clampedStart), nsString.length)
        let prefix = nsString.substring(with: NSRange(location: clampedStart, length: clampedEnd - clampedStart))

        let filtered = prefix.isEmpty
            ? completionItems
            : completionItems.filter { $0.label.lowercased().hasPrefix(prefix.lowercased()) }
        return filtered.isEmpty ? nil : filtered.map(Self.entry)
    }

    @MainActor
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let entry = item as? LSPCompletionEntry,
              let startPosition = completionPosition,
              let lspItem = completionItems.first(where: { $0.label == entry.label }) else {
            return
        }
        if lspItem.insertTextFormat == .snippet {
            applySnippetCompletion(
                lspItem,
                startPosition: startPosition,
                textView: textView,
                cursorPosition: cursorPosition
            )
            return
        }

        let edits = LSPCompletionItemsUtil.getCompletionItemEdits(startPosition: startPosition, item: lspItem)
        // Apply from the bottom up so offsets stay valid.
        let resolved = edits.compactMap { edit -> (NSRange, String)? in
            guard let range = textView.textView.nsRange(fromLSP: edit.range) else { return nil }
            return (range, edit.newText)
        }.sorted { $0.0.location > $1.0.location }
        for (range, text) in resolved {
            textView.textView.replaceCharacters(in: range, with: text)
        }
    }

    @MainActor
    func completionWindowDidClose() {
        completionPosition = nil
        completionItems = []
    }

    // MARK: - Mapping helpers

    static func entry(_ item: CompletionItem) -> LSPCompletionEntry {
        LSPCompletionEntry(
            label: item.label,
            detail: item.detail,
            documentation: item.documentation.map(plainText),
            insertText: item.insertText ?? item.label
        )
    }

    static func plainText(_ option: TwoTypeOption<String, MarkupContent>) -> String {
        switch option {
        case .optionA(let string): return string
        case .optionB(let content): return content.value
        }
    }

    static func plainText(_ option: TwoTypeOption<String, [UInt]>) -> String {
        switch option {
        case .optionA(let string): return string
        case .optionB(let offsets): return offsets.map(String.init).joined(separator: "-")
        }
    }

    private static func severity(_ severity: DiagnosticSeverity?) -> EditorDiagnosticSeverity {
        switch severity {
        case .error: return .error
        case .warning: return .warning
        case .information: return .info
        case .hint: return .hint
        case .none: return .error
        }
    }
}
