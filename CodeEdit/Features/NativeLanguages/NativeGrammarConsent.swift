//
//  NativeGrammarConsent.swift
//  CodeEdit
//
//  Explicit user consent for the native grammars an installed pack ships.
//

import Foundation
import CryptoKit

/// The native grammars of an installed pack that the user has explicitly trusted.
///
/// Consent is recorded per pack id + grammar path together with the SHA-256 the grammar had when the user
/// approved it. Replacing the grammar afterwards fails the load-time hash check instead of running new code.
struct NativeGrammarConsent: Equatable, Sendable {
    /// A native grammar declared by a pack's `contributes.syntax`.
    struct Declaration: Hashable, Sendable {
        let path: String
        let symbol: String
    }

    /// `key(packID:grammarPath:)` → the approved SHA-256.
    var recorded: [String: String] = [:]

    static let none = NativeGrammarConsent()

    /// The consent recorded in the app's preferences.
    static var current: NativeGrammarConsent {
        NativeGrammarConsent(recorded: AppServices.settings.preferences.extensions.nativeGrammarConsent)
    }

    static func key(packID: String, grammarPath: String) -> String {
        "\(packID)/\(grammarPath)"
    }

    func recordedHash(packID: String, grammarPath: String) -> String? {
        recorded[Self.key(packID: packID, grammarPath: grammarPath)]
    }

    /// The native grammars a pack declares, in declaration order.
    static func declarations(in ext: InstalledLanguageExtension) -> [Declaration] {
        (ext.manifest.contributes?.syntax ?? []).compactMap { syntax in
            guard syntax.grammar.kind == "native",
                  let path = syntax.grammar.path,
                  let symbol = syntax.grammar.symbol else { return nil }
            return Declaration(path: path, symbol: symbol)
        }
    }

    /// The SHA-256 of `url`'s contents, or `nil` when the file cannot be read.
    static func hashOfFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
