//
//  ExtensionLanguageProvider.swift
//  CodeEdit
//
//  A `LanguageProvider` backed by an out-of-process extension (JSON-RPC over stdio).
//

import Foundation
import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages
import CodeEditLang
import CodeEditLangPHP

// MARK: - Wire types

private struct CompletionParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let offset: Int
    let text: String
}

private struct HoverParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let offset: Int
    let text: String
}

private struct DefinitionParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let offset: Int
    let text: String
}

private struct SignatureHelpParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let offset: Int
    let argumentIndex: Int
    let text: String
}

private struct DiagnosticsParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let text: String
}

private struct SymbolsParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let text: String
}

private struct CodeActionParams: Encodable {
    let file: String
    let language: String
    let zone: ExtensionZoneContext
    let location: Int
    let length: Int
}

private struct ExtensionZoneContext: Encodable {
    let parentLanguageID: String?
    let sourceKey: String?
    let depth: Int
    let location: Int?
    let length: Int?

    init(_ context: LanguageZoneContext) {
        parentLanguageID = context.parentLanguageID?.rawValue
        sourceKey = context.sourceKey
        depth = context.depth
        location = context.range?.location
        length = context.range?.length
    }
}

private struct RPCCompletionItem: Decodable {
    let label: String
    let detail: String?
    let documentation: String?
    let insertText: String?
}

private struct RPCHover: Decodable {
    let contents: String
}

private struct RPCLocation: Decodable {
    let file: String?
    let location: Int
    let length: Int?
}

private struct RPCSignature: Decodable {
    let signature: String
    let parameters: [String]?
    let activeParameter: Int?
}

private struct RPCDiagnostic: Decodable {
    let location: Int
    let length: Int?
    let severity: String?
    let message: String
    let line: Int?
    let languageID: String?
    let parentLanguageID: String?
    let sourceKey: String?
    let depth: Int?
    let zoneLocation: Int?
    let zoneLength: Int?
}

private struct RPCSymbol: Decodable {
    let name: String
    let detail: String?
    let location: Int
    let languageID: String?
    let parentLanguageID: String?
    let sourceKey: String?
    let depth: Int?
    let zoneLocation: Int?
    let zoneLength: Int?
}

private struct RPCEdit: Decodable {
    let location: Int
    let length: Int
    let text: String
}

private struct RPCCodeAction: Decodable {
    let title: String
    let kind: String?
    let edits: [RPCEdit]
    let languageID: String?
    let parentLanguageID: String?
    let sourceKey: String?
    let depth: Int?
    let zoneLocation: Int?
    let zoneLength: Int?
}

// MARK: - Completion item

/// A completion entry produced by a programmatic extension.
private struct ExtensionCompletionItem: CodeSuggestionEntry {
    let label: String
    let detail: String?
    let documentation: String?
    let insertText: String

    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var image: Image { Image(systemName: "puzzlepiece.extension") }
    var imageColor: Color { Color(NSColor.systemTeal) }
    var deprecated: Bool { false }
}

// MARK: - Provider

/// A language provider backed by an out-of-process extension process.
final class ExtensionLanguageProvider: LanguageProvider {
    let languageID: String
    let supportedLanguageIDs: Set<String>
    let priority: LanguageProviderPriority = .languageExtension

    /// Providers written before `completionTriggers` existed keep the original PHP-oriented triggers.
    static let legacyCompletionTriggers: Set<String> = ["\\", ">", ":"]

    private let fileURL: URL
    private let server: StdioLanguageServer
    private let openLinkHandler: (JumpToDefinitionLink) -> Void
    private let completionTriggers: Set<String>

    private var lastItems: [ExtensionCompletionItem] = []
    private var lastItemsPrefix = ""

    init(
        languageIDs: Set<String>,
        fileURL: URL,
        server: StdioLanguageServer,
        completionTriggers: [String]? = nil,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) {
        let languageID = languageIDs.sorted().first ?? ""
        self.languageID = languageID
        self.supportedLanguageIDs = languageIDs
        self.fileURL = fileURL
        self.server = server
        self.completionTriggers = Self.resolvedCompletionTriggers(completionTriggers)
        self.openLinkHandler = openLink
    }

    /// `nil` keeps legacy behavior; an explicit empty array disables automatic triggers.
    static func resolvedCompletionTriggers(_ configured: [String]?) -> Set<String> {
        guard let configured else { return legacyCompletionTriggers }
        return Set(configured)
    }

    private var filePath: String { fileURL.path(percentEncoded: false) }

    private func zoneContext(at location: Int, in textView: TextViewController) -> LanguageZoneContext {
        textView.languageContexts(at: location).first(where: {
            supportedLanguageIDs.contains($0.languageID.rawValue)
        }) ?? LanguageZoneContext(languageID: textView.language.id)
    }

    private func responseContext(
        languageID: String?,
        parentLanguageID: String?,
        sourceKey: String?,
        depth: Int?,
        zoneLocation: Int? = nil,
        zoneLength: Int? = nil,
        fallback: LanguageZoneContext
    ) -> LanguageZoneContext {
        let resolvedLanguage = languageID.flatMap { supportedLanguageIDs.contains($0) ? LanguageID(rawValue: $0) : nil }
            ?? fallback.languageID
        let resolvedParent = parentLanguageID.map { LanguageID(rawValue: $0) } ?? fallback.parentLanguageID
        return LanguageZoneContext(
            languageID: resolvedLanguage,
            parentLanguageID: resolvedParent,
            sourceKey: sourceKey ?? fallback.sourceKey,
            depth: max(0, depth ?? fallback.depth),
            range: zoneLocation.map {
                NSRange(location: max(0, $0), length: max(0, zoneLength ?? 0))
            } ?? fallback.range
        )
    }

    // MARK: JumpToDefinitionDelegate

    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        let context = zoneContext(at: range.location, in: textView)
        let params = DefinitionParams(
            file: filePath,
            language: context.languageID.rawValue,
            zone: ExtensionZoneContext(context),
            offset: range.location,
            text: textView.textView.string
        )
        guard let locations = try? await server.request("definition", params: params, as: [RPCLocation].self),
              !locations.isEmpty else {
            return nil
        }

        return locations.map { location in
            let url = location.file.map { URL(fileURLWithPath: $0) }
            return JumpToDefinitionLink(
                url: url == fileURL ? nil : url,
                targetRange: CursorPosition(range: NSRange(location: location.location, length: location.length ?? 0)),
                typeName: fileURL.lastPathComponent,
                sourcePreview: location.file ?? fileURL.lastPathComponent,
                documentation: nil,
                image: Image(systemName: "puzzlepiece.extension"),
                imageColor: Color(NSColor.systemTeal)
            )
        }
    }

    func openLink(link: JumpToDefinitionLink) {
        openLinkHandler(link)
    }

    // MARK: HoverDelegate

    @MainActor
    func hoverInfo(forRange range: NSRange, textView: TextViewController) async -> HoverInfo? {
        let context = zoneContext(at: range.location, in: textView)
        let params = HoverParams(
            file: filePath,
            language: context.languageID.rawValue,
            zone: ExtensionZoneContext(context),
            offset: range.location,
            text: textView.textView.string
        )
        guard let hover = try? await server.request("hover", params: params, as: RPCHover?.self),
              !hover.contents.isEmpty else {
            return nil
        }
        return HoverInfo(contents: hover.contents, range: range)
    }

    // MARK: SignatureHelpDelegate

    @MainActor
    func signatureHelp(
        calleeRange: NSRange,
        argumentIndex: Int,
        textView: TextViewController
    ) async -> SignatureHelpInfo? {
        let context = zoneContext(at: calleeRange.location, in: textView)
        let params = SignatureHelpParams(
            file: filePath,
            language: context.languageID.rawValue,
            zone: ExtensionZoneContext(context),
            offset: calleeRange.location,
            argumentIndex: argumentIndex,
            text: textView.textView.string
        )
        guard let signature = try? await server.request("signatureHelp", params: params, as: RPCSignature?.self) else {
            return nil
        }
        return SignatureHelpInfo(
            signature: signature.signature,
            parameters: signature.parameters ?? [],
            activeParameter: signature.activeParameter ?? argumentIndex
        )
    }

    // MARK: SymbolsDelegate

    @MainActor
    func documentSymbols(for textView: TextViewController) async -> [EditorSymbol] {
        let rootContext = LanguageZoneContext(languageID: textView.language.id)
        let params = SymbolsParams(
            file: filePath,
            language: textView.language.id.rawValue,
            zone: ExtensionZoneContext(LanguageZoneContext(languageID: textView.language.id)),
            text: textView.textView.string
        )
        guard let symbols = try? await server.request("documentSymbols", params: params, as: [RPCSymbol].self) else {
            return []
        }
        return symbols.map {
            EditorSymbol(
                name: $0.name,
                detail: $0.detail,
                position: CursorPosition(range: NSRange(location: $0.location, length: 0)),
                languageContext: responseContext(
                    languageID: $0.languageID,
                    parentLanguageID: $0.parentLanguageID,
                    sourceKey: $0.sourceKey,
                    depth: $0.depth,
                    zoneLocation: $0.zoneLocation,
                    zoneLength: $0.zoneLength,
                    fallback: rootContext
                )
            )
        }
    }

    // MARK: DiagnosticsDelegate

    @MainActor
    func diagnostics(for textView: TextViewController) async -> [EditorDiagnostic] {
        let rootContext = LanguageZoneContext(languageID: textView.language.id)
        let params = DiagnosticsParams(
            file: filePath,
            language: textView.language.id.rawValue,
            zone: ExtensionZoneContext(LanguageZoneContext(languageID: textView.language.id)),
            text: textView.textView.string
        )
        guard let diagnostics = try? await server.request(

            "diagnostics",

            params: params,

            as: [RPCDiagnostic].self

        ) else {
            return []
        }
        return diagnostics.map { diagnostic in
            EditorDiagnostic(
                range: NSRange(location: diagnostic.location, length: diagnostic.length ?? 0),
                severity: Self.severity(from: diagnostic.severity),
                message: diagnostic.message,
                line: diagnostic.line,
                languageContext: responseContext(
                    languageID: diagnostic.languageID,
                    parentLanguageID: diagnostic.parentLanguageID,
                    sourceKey: diagnostic.sourceKey,
                    depth: diagnostic.depth,
                    zoneLocation: diagnostic.zoneLocation,
                    zoneLength: diagnostic.zoneLength,
                    fallback: rootContext
                )
            )
        }
    }

    // MARK: CodeActionDelegate

    @MainActor
    func codeActions(forRange range: NSRange, textView: TextViewController) async -> [CodeActionInfo] {
        let context = zoneContext(at: range.location, in: textView)
        let params = CodeActionParams(
            file: filePath,
            language: context.languageID.rawValue,
            zone: ExtensionZoneContext(context),
            location: range.location,
            length: range.length
        )
        guard let actions = try? await server.request("codeActions", params: params, as: [RPCCodeAction].self) else {
            return []
        }
        return actions.map { action in
            let context = responseContext(
                languageID: action.languageID,
                parentLanguageID: action.parentLanguageID,
                sourceKey: action.sourceKey,
                depth: action.depth,
                zoneLocation: action.zoneLocation,
                zoneLength: action.zoneLength,
                fallback: context
            )
            return CodeActionInfo(
                title: action.title,
                kind: action.kind,
                edits: action.edits.map {
                    CodeActionEdit(range: NSRange(location: $0.location, length: $0.length), text: $0.text)
                },
                languageContext: context
            )
        }
    }

    // MARK: CodeSuggestionDelegate

    @MainActor
    func completionTriggerCharacters() -> Set<String> { completionTriggers }

    @MainActor
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        let source = textView.textView.string
        let offset = cursorPosition.range.location
        let context = zoneContext(at: offset, in: textView)
        let params = CompletionParams(
            file: filePath,
            language: context.languageID.rawValue,
            zone: ExtensionZoneContext(context),
            offset: offset,
            text: source
        )
        guard let items = try? await server.request("completion", params: params, as: [RPCCompletionItem].self),
              !items.isEmpty else {
            lastItems = []
            return nil
        }
        lastItems = items.map {
            ExtensionCompletionItem(
                label: $0.label,
                detail: $0.detail,
                documentation: $0.documentation,
                insertText: $0.insertText ?? $0.label
            )
        }
        lastItemsPrefix = Self.prefix(in: source, before: offset)
        return (cursorPosition, lastItems)
    }

    @MainActor
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        let source = textView.textView.string
        let prefix = Self.prefix(in: source, before: cursorPosition.range.location)
        let filtered = lastItems.filter { $0.label.lowercased().hasPrefix(prefix.lowercased()) }
        return filtered.isEmpty ? nil : filtered
    }

    @MainActor
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let cursorPosition else { return }
        let source = textView.textView.string
        let offset = cursorPosition.range.location
        let insertText = (item as? ExtensionCompletionItem)?.insertText ?? item.label
        let start = offset - Self.prefix(in: source, before: offset).count
        textView.textView.replaceCharacters(in: NSRange(location: start, length: offset - start), with: insertText)
    }

    // MARK: Helpers

    private static func prefix(in source: String, before offset: Int) -> String {
        let nsString = source as NSString
        let safeOffset = min(max(offset, 0), nsString.length)
        var index = safeOffset
        while index > 0 {
            let scalar = nsString.character(at: index - 1)
            guard let unicode = UnicodeScalar(scalar),
                  CharacterSet.alphanumerics.contains(unicode) || unicode == "_" || unicode == "\\" else {
                break
            }
            index -= 1
        }
        return nsString.substring(with: NSRange(location: index, length: safeOffset - index))
    }

    private static func severity(from string: String?) -> EditorDiagnosticSeverity {
        switch string?.lowercased() {
        case "warning": return .warning
        case "info": return .info
        case "hint": return .hint
        default: return .error
        }
    }
}
