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
/// The loader is pure: it reads manifests and query files and returns languages plus diagnostics. It
/// never mutates a registry — ``LanguageCatalogStore`` owns caching and the merge into a workspace
/// catalog.
struct SyntaxContributionLoader {
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
    func load(_ extensions: [InstalledLanguageExtension], base: LanguageCatalog) -> [PackOutcome] {
        let context = LanguageExtensionValidationContext(
            known: Self.knownLanguages(in: base),
            allowsNativeGrammars: false,
            hostVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )

        return extensions.map { ext in
            var outcome = PackOutcome(
                extensionID: ext.id,
                extensionName: ext.name,
                extensionVersion: ext.version
            )

            let validation = LanguageExtensionValidator.validate(
                manifest: ext.manifest, root: ext.root, context: context
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

            for (index, syntax) in (ext.manifest.contributes?.syntax ?? []).enumerated() {
                let location = "contributes.syntax[\(index)]"
                guard let language = makeLanguage(
                    syntax, packRoot: ext.root, location: location, base: base, into: &outcome.issues
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

    // MARK: - One contribution

    private func makeLanguage(
        _ syntax: LanguageExtensionManifest.Contributes.Syntax,
        packRoot: URL,
        location: String,
        base: LanguageCatalog,
        into issues: inout [LanguageExtensionIssue]
    ) -> CodeLanguage? {
        guard let baseLanguage = baseLanguage(
            for: syntax.grammar, location: location, base: base, into: &issues
        ), let treeSitterLanguage = baseLanguage.grammar.builtInLanguage else {
            return nil
        }

        guard let queries = resolveQueries(syntax.queries, packRoot: packRoot, location: location, into: &issues),
              let queryURLs = compileQueries(
                  queries, using: baseLanguage, location: location, into: &issues
              ) else {
            return nil
        }

        // `parent` becomes the inherited highlights query; every other auxiliary query is merged into
        // the highlights query at runtime, matching the built-in language convention.
        let extraQueries = Set(queryURLs.keys).subtracting(["highlights", "parent"])
        let id = syntax.id.trimmingCharacters(in: .whitespacesAndNewlines)

        return CodeLanguage(
            id: LanguageID(rawValue: id),
            tsName: syntax.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? id,
            extensions: detectionExtensions(syntax),
            lineCommentString: baseLanguage.lineCommentString,
            rangeCommentStrings: baseLanguage.rangeCommentStrings,
            documentationCommentStrings: baseLanguage.documentationCommentStrings,
            grammar: GrammarReference(identifier: treeSitterLanguage.rawValue, builtInLanguage: treeSitterLanguage),
            highlights: extraQueries.isEmpty ? nil : extraQueries,
            additionalIdentifiers: detectionIdentifiers(syntax),
            queryURLs: queryURLs,
            firstLinePatterns: syntax.firstLinePatterns ?? []
        )
    }

    /// The built-in language whose grammar a pack reuses, or `nil` with a diagnostic.
    private func baseLanguage(
        for grammar: LanguageExtensionManifest.Contributes.Syntax.Grammar,
        location: String,
        base: LanguageCatalog,
        into issues: inout [LanguageExtensionIssue]
    ) -> CodeLanguage? {
        guard grammar.kind == "builtin" else {
            issues.append(.error(
                "Grammar kind '\(grammar.kind)' cannot be loaded in this version of CodeEdit.",
                at: "\(location).grammar"
            ))
            return nil
        }

        let name = grammar.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            issues.append(.error("Built-in grammar requires `name`.", at: "\(location).grammar"))
            return nil
        }

        guard let language = base.language(forIdentifier: name), language.grammar.builtInLanguage != nil else {
            issues.append(.error("Unknown built-in grammar '\(name)'.", at: "\(location).grammar"))
            return nil
        }

        return language
    }

    /// Resolves every declared query inside the pack root.
    ///
    /// Existence and type are already checked by ``LanguageExtensionValidator``; this only re-asserts
    /// containment because a query is read straight from disk here.
    private func resolveQueries(
        _ queries: LanguageExtensionManifest.Contributes.Syntax.Queries,
        packRoot: URL,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> [(name: String, url: URL)]? {
        var resolved: [(name: String, url: URL)] = []

        for (name, path) in queries.namedPaths {
            guard let url = LanguageExtensionPaths.resolve(path, in: packRoot),
                  LanguageExtensionPaths.isContained(url, in: packRoot) else {
                issues.append(.error(
                    "\(name.capitalized) query escapes the pack: \(path)",
                    at: "\(location).queries.\(name)"
                ))
                return nil
            }
            resolved.append((name: name, url: url))
        }

        return resolved
    }

    /// Compiles every query, dropping the ones that are malformed.
    ///
    /// A broken highlights query returns `nil`: the language would have nothing to highlight. A broken
    /// auxiliary query is dropped instead — it is merged into the highlights query at runtime, so
    /// keeping it would take the language's highlighting down with it.
    ///
    /// - Returns: The compiled query URLs keyed by query name, or `nil` when the highlights query is
    ///   malformed.
    private func compileQueries(
        _ queries: [(name: String, url: URL)],
        using baseLanguage: CodeLanguage,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> [String: URL]? {
        var urls: [String: URL] = [:]
        var highlightCaptures = Set<String>()
        var failures: [String: String] = [:]

        for (name, url) in queries {
            do {
                let captures = try baseLanguage.compileQuery(at: url)
                urls[name] = url
                // Only the highlights query renders captures. Fold/indent/local/tag queries have their
                // own capture vocabularies that the highlighter legitimately ignores.
                if name == "highlights" {
                    highlightCaptures.formUnion(captures)
                }
            } catch {
                failures[name] = String(describing: error)
            }
        }

        if let message = failures["highlights"] {
            issues.append(.error(
                "Highlights query failed to compile: \(message)", at: "\(location).queries.highlights"
            ))
            return nil
        }

        for name in failures.keys.sorted() {
            issues.append(.error(
                "\(name.capitalized) query failed to compile and was dropped: \(failures[name] ?? "")",
                at: "\(location).queries.\(name)"
            ))
        }

        for capture in highlightCaptures.sorted() where !CaptureName.isKnown(capture) {
            issues.append(.warning(
                "Unknown capture '@\(capture)' — it will not be highlighted.",
                at: "\(location).queries.highlights"
            ))
        }

        return urls
    }

    /// The extensions and exact file names that select a contributed language.
    private func detectionExtensions(
        _ syntax: LanguageExtensionManifest.Contributes.Syntax
    ) -> Set<String> {
        var result = Set<String>()

        for raw in syntax.extensions ?? [] {
            let normalized = LanguageExtensionValidator.normalizeExtension(raw)
            if !normalized.isEmpty {
                result.insert(normalized)
            }
        }
        for raw in syntax.filenames ?? [] {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                result.insert(name)
            }
        }

        return result
    }

    /// The extra identifiers a contributed language answers to: aliases and shebang names.
    private func detectionIdentifiers(
        _ syntax: LanguageExtensionManifest.Contributes.Syntax
    ) -> Set<String> {
        var result = Set<String>()

        for raw in (syntax.aliases ?? []) + (syntax.shebangs ?? []) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result.insert(value)
            }
        }

        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
