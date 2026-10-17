//
//  LSPLanguageProvider+Editor.swift
//  CodeEdit
//
//  Editor-adapter requests: inlay hints, document highlights, and folding ranges.
//

import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

extension LSPLanguageProvider {
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

    @MainActor
    func inlayHints(forVisibleRange range: NSRange, textView: TextViewController) async -> [EditorInlayHint] {
        // Skip when the server doesn't advertise inlay hints (avoids -32601 for servers like the CSS one).
        guard let server = server,
              server.serverCapabilities.inlayHintProvider != nil,
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

    @MainActor
    func documentHighlights(
        at position: CursorPosition,
        textView: TextViewController
    ) async -> [EditorDocumentHighlight] {
        guard let server = server,
              let lspPosition = textView.textView.lspRangeFrom(nsRange: position.range)?.start else {
            return []
        }
        guard let highlights = try? await server.requestHighlight(
            for: documentURI,
            position: lspPosition
        ) else {
            return []
        }
        return highlights.compactMap { highlight in
            guard let range = textView.textView.nsRange(fromLSP: highlight.range) else { return nil }
            return EditorDocumentHighlight(range: range, kind: highlight.kind?.rawValue)
        }
    }

    @MainActor
    func foldRanges(for textView: TextViewController) async -> [EditorFoldRange] {
        guard let server = server,
              let ranges = try? await server.requestFoldingRange(for: documentURI) else {
            return []
        }
        return ranges.compactMap { range in
            guard range.endLine > range.startLine else { return nil }
            return EditorFoldRange(
                startLine: range.startLine,
                endLine: range.endLine,
                kind: range.kind?.rawValue
            )
        }
    }
}
