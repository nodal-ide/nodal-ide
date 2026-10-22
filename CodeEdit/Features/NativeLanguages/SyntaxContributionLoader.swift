//
//  SyntaxContributionLoader.swift
//  CodeEdit
//
//  Builds the languages contributed by declarative extension syntax packs.
//

import Foundation
import CodeEditLang
import CodeEditLanguages
import CodeEditSourceEditor
import os

private let syntaxLoaderLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "",
    category: "SyntaxContributions"
)

/// Turns `contributes.syntax` entries into ``CodeLanguage`` values.
///
/// Builds language descriptors and diagnostics. ``LanguageCatalogStore`` owns caching and catalog merges.
struct SyntaxContributionLoader {
    struct BuildContext {
        let pack: InstalledLanguageExtension
        let base: LanguageCatalog
        let consent: NativeGrammarConsent
        let validatesNativeGrammar: Bool
    }

    /// What one pack contributed, and everything that stopped it from contributing more.
    struct PackOutcome {
        let extensionID: String
        let extensionName: String
        /// The contributing extension's version, when declared. Shown by the inspector's language list.
        let extensionVersion: String?
        /// Languages built from this pack's `contributes.syntax`, in declaration order.
        var languages: [CodeLanguage] = []
        /// Validation and loading problems for this pack.
        var issues: [LanguageExtensionIssue] = []
    }

    /// Builds every syntax contribution of `extensions`, one outcome per pack.
    ///
    /// A pack that the shared validator rejects contributes no languages; its issues are still
    /// returned so the Extensions UI can explain what is wrong with it.
    ///
    /// - Parameters:
    ///   - extensions: Packs already filtered to those enabled and active in the workspace, in load
    ///     order. A built-in language always wins over a contributed one with the same id.
    ///   - base: The catalog contributed languages are built on top of. It supplies the built-in
    ///     grammars a pack may reuse and the built-in identifiers conflicts are checked against.
    ///   - consent: The native grammars the user has trusted. A native grammar without recorded consent
    ///     contributes nothing but an actionable error.
    ///   - validateNativeGrammarsFor: Pack IDs whose native grammar and queries should be loaded and
    ///     compiled now. Catalog builds leave this empty to keep native loading lazy.
    func load(
        _ extensions: [InstalledLanguageExtension],
        base: LanguageCatalog,
        consent: NativeGrammarConsent = .none,
        validateNativeGrammarsFor: Set<String> = []
    ) -> [PackOutcome] {
        let known = Self.knownLanguages(in: base)
        let hostVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        return extensions.map { ext in
            var outcome = PackOutcome(
                extensionID: ext.id,
                extensionName: ext.name,
                extensionVersion: ext.version
            )

            let validation = LanguageExtensionValidator.validate(
                manifest: ext.manifest,
                root: ext.root,
                context: LanguageExtensionValidationContext(
                    known: known,
                    allowsNativeGrammars: true,
                    scope: ext.scope,
                    hostVersion: hostVersion
                )
            )
            outcome.issues.append(contentsOf: validation.issues)

            guard validation.isValid else {
                syntaxLoaderLogger.error(
                    """
                    Skipping language extension \(ext.id, privacy: .public): \
                    \(validation.errors.count, privacy: .public) validation error(s).
                    """
                )
                return outcome
            }

            let context = BuildContext(
                pack: ext,
                base: base,
                consent: consent,
                validatesNativeGrammar: validateNativeGrammarsFor.contains(ext.id)
            )

            for (index, syntax) in (ext.manifest.contributes?.syntax ?? []).enumerated() {
                let location = "contributes.syntax[\(index)]"
                guard let language = makeLanguage(
                    syntax, context: context, location: location, into: &outcome.issues
                ) else {
                    continue
                }
                outcome.languages.append(language)
            }

            return outcome
        }
    }

    /// Drops contributed languages whose id is already provided by another enabled pack.
    ///
    /// The shared validator judges each pack in isolation, so an id clash between two packs can only
    /// be seen once all of the workspace's packs are known. The first pack in load order wins; the
    /// ignored contribution is reported on the losing pack so the Extensions UI can explain it.
    ///
    /// A repeated detection key is not fatal — the catalog resolves it deterministically (the first
    /// language in catalog order owns the key) — but it is reported as a warning.
    static func resolveConflicts(_ outcomes: [PackOutcome]) -> [PackOutcome] {
        var idOwners: [String: String] = [:]
        var detectionKeyOwners: [String: String] = [:]
        var resolved: [PackOutcome] = []

        for var outcome in outcomes {
            var kept: [CodeLanguage] = []

            for language in outcome.languages {
                let idKey = language.id.rawValue.lowercased()
                if let owner = idOwners[idKey] {
                    outcome.issues.append(.error(
                        "Language '\(language.id.rawValue)' is already provided by extension "
                            + "'\(owner)'; this contribution was ignored.",
                        at: "contributes.syntax"
                    ))
                    continue
                }

                for key in language.extensions.sorted() {
                    let normalized = key.lowercased()
                    if let owner = detectionKeyOwners[normalized] {
                        outcome.issues.append(.warning(
                            "'\(key)' is also mapped by extension '\(owner)'; that mapping wins.",
                            at: "contributes.syntax"
                        ))
                    } else {
                        detectionKeyOwners[normalized] = outcome.extensionID
                    }
                }

                idOwners[idKey] = outcome.extensionID
                kept.append(language)
            }

            outcome.languages = kept
            resolved.append(outcome)
        }

        return resolved
    }

    // MARK: - Catalog knowledge

    /// The built-in identifiers, extensions and file names a pack's contributions are checked against.
    ///
    /// `CodeLanguage` stores file names and extensions in one `extensions` set (for example
    /// `Dockerfile`, `.env`), so both keys are derived from it: the dot-stripped form feeds
    /// `extensions`, the raw form feeds `fileNames`.
    static func knownLanguages(in catalog: LanguageCatalog) -> LanguageExtensionKnownLanguages {
        var identifiers = Set<String>()
        var extensions = Set<String>()
        var fileNames = Set<String>()

        for language in catalog.languages {
            identifiers.insert(language.id.rawValue.lowercased())
            identifiers.insert(language.tsName.lowercased())
            identifiers.formUnion(language.additionalIdentifiers.map { $0.lowercased() })

            for entry in language.extensions {
                let normalized = LanguageExtensionValidator.normalizeExtension(entry)
                if !normalized.isEmpty {
                    extensions.insert(normalized)
                }
                fileNames.insert(entry.lowercased())
            }
        }

        return LanguageExtensionKnownLanguages(
            identifiers: identifiers,
            extensions: extensions,
            fileNames: fileNames
        )
    }

}
