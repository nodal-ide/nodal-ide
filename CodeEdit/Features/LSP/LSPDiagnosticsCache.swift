//
//  LSPDiagnosticsCache.swift
//  CodeEdit
//
//  Stores the latest push diagnostics (`textDocument/publishDiagnostics`) per document URI.
//

import Foundation
import LanguageServerProtocol

/// Servers like `typescript-language-server` push diagnostics rather than answering pull requests.
/// The editor's diagnostics model reads those through this cache.
@MainActor
final class LSPDiagnosticsCache {
    static let shared = LSPDiagnosticsCache()

    private var byURI: [String: [Diagnostic]] = [:]

    private init() {}

    func update(uri: String, diagnostics: [Diagnostic]) {
        byURI[uri] = diagnostics
    }

    func diagnostics(for uri: String) -> [Diagnostic] {
        byURI[uri] ?? []
    }

    func clear(uri: String) {
        byURI[uri] = nil
    }
}
