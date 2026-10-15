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
import CodeEditLangPHP
import LanguageServerProtocol

/// A completion entry produced by a language server.
private struct LSPCompletionEntry: CodeSuggestionEntry {
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
final class LSPLanguageProvider: LanguageProvider {
    let languageID: String
    let priority: LanguageProviderPriority = .lsp

    private let fileURL: URL
    private let workspacePath: String
    private let openLinkHandler: (JumpToDefinitionLink) -> Void

    /// The running server for this file's language, resolved lazily (it may still be starting when the
    /// file is opened).
    private var server: LanguageServer<CodeFileDocument>? {
        MainActor.assumeIsolated {
            guard let lsp = ServiceContainer.resolve(.singleton, LSPService.self),
                  let language = LanguageIdentifier(rawValue: languageID) else {
                return nil
            }
            return lsp.languageClient(for: language, workspacePath: workspacePath)
        }
    }

    /// The last completion request: the LSP position and the items it returned.
    private var completionPosition: Position?
    private var completionItems: [CompletionItem] = []

    private var documentURI: String { fileURL.lspURI }

    nonisolated init(
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
        guard let server = server, let position = textView.textView.lspRangeFrom(nsRange: range)?.start else { return nil }
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
        guard let server = server, let position = textView.textView.lspRangeFrom(nsRange: range)?.start else { return nil }
        guard let hover = try? await server.requestHover(for: documentURI, position) else { return nil }
        let contents = Self.hoverText(hover.contents)
        guard !contents.isEmpty else { return nil }
        return HoverInfo(contents: contents, range: range)
    }

    // MARK: - Signature help

    @MainActor
    func signatureHelp(
        calleeRange: NSRange,
        argumentIndex: Int,
        textView: TextViewController
    ) async -> SignatureHelpInfo? {
        guard let server = server, let position = textView.textView.lspRangeFrom(nsRange: calleeRange)?.start else {
            return nil
        }
        guard let help = try? await server.requestSignatureHelp(for: documentURI, position),
              let signature = help.signatures.first else {
            return nil
        }
        let parameters = (signature.parameters ?? []).map { Self.plainText($0.label) }
        let active = help.activeParameter ?? signature.activeParameter.map { Int($0) } ?? argumentIndex
        return SignatureHelpInfo(signature: signature.label, parameters: parameters, activeParameter: active)
    }

    // MARK: - Document symbols

    @MainActor
    func documentSymbols(for textView: TextViewController) async -> [EditorSymbol] {
        guard let server = server, let response = try? await server.requestSymbols(for: documentURI) else {
            return []
        }

        var result: [EditorSymbol] = []
        switch response {
        case .optionA(let symbols):
            func add(_ symbol: DocumentSymbol) {
                result.append(
                    EditorSymbol(
                        name: symbol.name,
                        detail: symbol.detail,
                        position: CursorPosition(
                            line: symbol.selectionRange.start.line + 1,
                            column: symbol.selectionRange.start.character + 1
                        )
                    )
                )
                symbol.children?.forEach(add)
            }
            symbols.forEach(add)
        case .optionB(let infos):
            for info in infos {
                result.append(
                    EditorSymbol(
                        name: info.name,
                        detail: info.containerName,
                        position: CursorPosition(
                            line: info.location.range.start.line + 1,
                            column: info.location.range.start.character + 1
                        )
                    )
                )
            }
        }
        return result
    }

    // MARK: - Diagnostics

    @MainActor
    func diagnostics(for textView: TextViewController) async -> [EditorDiagnostic] {
        guard let server = server, let report = try? await server.requestPullDiagnostics(document: documentURI) else {
            return []
        }
        return (report.items ?? []).compactMap { diagnostic in
            guard let range = textView.textView.nsRange(fromLSP: diagnostic.range) else { return nil }
            return EditorDiagnostic(
                range: range,
                severity: Self.severity(diagnostic.severity),
                message: diagnostic.message,
                line: diagnostic.range.start.line + 1
            )
        }
    }

    // MARK: - Code actions

    @MainActor
    func codeActions(forRange range: NSRange, textView: TextViewController) async -> [CodeActionInfo] {
        guard let server = server,
              let lspRange = textView.textView.lspRangeFrom(nsRange: range) else {
            return []
        }
        let diagnostics = (try? await server.requestPullDiagnostics(document: documentURI))?.items ?? []
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

    // MARK: - Inlay hints

    @MainActor
    func inlayHints(forVisibleRange range: NSRange, textView: TextViewController) async -> [EditorInlayHint] {
        guard let server = server,
              let lspRange = textView.textView.lspRangeFrom(nsRange: range) else {
            return []
        }
        guard let hints = try? await server.requestInlayHint(for: documentURI, lspRange) else {
            return []
        }
        return hints.compactMap { hint in
            guard let offset = textView.textView.offset(forLSPPosition: hint.position) else { return nil }
            let label: String
            switch hint.label {
            case .optionA(let string):
                label = string
            case .optionB(let parts):
                label = parts.map(\.value).joined()
            }
            guard !label.isEmpty else { return nil }
            return EditorInlayHint(offset: offset, text: label)
        }
    }

    // MARK: - Completion

    @MainActor
    func completionTriggerCharacters() -> Set<String> { [] }

    @MainActor
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let server = server, let position = textView.textView.lspRangeFrom(nsRange: cursorPosition.range)?.start else {
            return nil
        }
        guard let response = try? await server.requestCompletion(for: documentURI, position: position) else {
            return nil
        }

        let items: [CompletionItem]
        switch response {
        case .optionA(let array):
            items = array
        case .optionB(let list):
            items = list.items
        }
        guard !items.isEmpty else {
            completionPosition = nil
            completionItems = []
            return nil
        }

        completionPosition = position
        completionItems = Array(items.prefix(500))
        return (cursorPosition, completionItems.map(Self.entry))
    }

    @MainActor
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard let startPosition = completionPosition, !completionItems.isEmpty else { return nil }
        let prefixStart = textView.textView.offset(forLSPPosition: startPosition) ?? 0
        let cursor = cursorPosition.range.location
        let ns = textView.textView.string as NSString
        let clampedStart = min(max(prefixStart, 0), ns.length)
        let clampedEnd = min(max(cursor, clampedStart), ns.length)
        let prefix = ns.substring(with: NSRange(location: clampedStart, length: clampedEnd - clampedStart))

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

    private static func entry(_ item: CompletionItem) -> LSPCompletionEntry {
        LSPCompletionEntry(
            label: item.label,
            detail: item.detail,
            documentation: item.documentation.map(plainText),
            insertText: item.insertText ?? item.label
        )
    }

    private static func plainText(_ option: TwoTypeOption<String, MarkupContent>) -> String {
        switch option {
        case .optionA(let string): return string
        case .optionB(let content): return content.value
        }
    }

    private static func plainText(_ option: TwoTypeOption<String, [UInt]>) -> String {
        switch option {
        case .optionA(let string): return string
        case .optionB(let offsets): return offsets.map(String.init).joined(separator: "-")
        }
    }

    private static func hoverText(_ contents: ThreeTypeOption<MarkedString, [MarkedString], MarkupContent>) -> String {
        switch contents {
        case .optionA(let marked): return marked.value
        case .optionB(let markedArray): return markedArray.map(\.value).joined(separator: "\n\n")
        case .optionC(let content): return content.value
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
