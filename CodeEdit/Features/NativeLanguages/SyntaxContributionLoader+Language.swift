//
//  SyntaxContributionLoader+Language.swift
//  CodeEdit
//

import Foundation
import CodeEditLang
import CodeEditLanguages
import CodeEditSourceEditor

extension SyntaxContributionLoader {
    private struct ResolvedGrammar {
        var grammar: GrammarReference
        var lineCommentString: String
        var rangeCommentStrings: (String, String)
        var documentationCommentStrings: Set<DocumentationComments>
    }

    private struct LanguageMetadata {
        let id: String
        let syntax: LanguageExtensionManifest.Contributes.Syntax
        let extensions: Set<String>
        let identifiers: Set<String>
        let firstLinePatterns: [String]
        let resolved: ResolvedGrammar
    }

    func makeLanguage(
        _ syntax: LanguageExtensionManifest.Contributes.Syntax,
        context: BuildContext,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> CodeLanguage? {
        guard var resolved = resolveGrammar(
            syntax.grammar, context: context, location: location, into: &issues
        ) else {
            return nil
        }
        applyComments(syntax.comments, to: &resolved)
        guard validateNativeGrammarIfRequested(
            resolved, context: context, location: location, into: &issues
        ) else {
            return nil
        }

        let metadata = LanguageMetadata(
            id: syntax.id.trimmingCharacters(in: .whitespacesAndNewlines),
            syntax: syntax,
            extensions: detectionExtensions(syntax),
            identifiers: detectionIdentifiers(syntax),
            firstLinePatterns: syntax.firstLinePatterns ?? [],
            resolved: resolved
        )
        guard let queries = resolveQueries(
            syntax.queries, packRoot: context.pack.root, location: location, into: &issues
        ) else {
            return nil
        }

        let queryURLs: [String: URL]
        if resolved.grammar.native != nil && !context.validatesNativeGrammar {
            queryURLs = Dictionary(uniqueKeysWithValues: queries.map { ($0.name, $0.url) })
        } else {
            let baseLanguage = makeLanguage(metadata: metadata, queryURLs: [:])
            guard let compiled = compileQueries(queries, using: baseLanguage, location: location, into: &issues) else {
                return nil
            }
            queryURLs = compiled
        }

        return makeLanguage(metadata: metadata, queryURLs: queryURLs)
    }

    private func makeLanguage(
        metadata: LanguageMetadata,
        queryURLs: [String: URL]
    ) -> CodeLanguage {
        let extraQueries = Set(queryURLs.keys).subtracting(["highlights", "parent"])
        return CodeLanguage(
            id: LanguageID(rawValue: metadata.id),
            tsName: metadata.syntax.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? metadata.id,
            extensions: metadata.extensions,
            lineCommentString: metadata.resolved.lineCommentString,
            rangeCommentStrings: metadata.resolved.rangeCommentStrings,
            documentationCommentStrings: metadata.resolved.documentationCommentStrings,
            grammar: metadata.resolved.grammar,
            highlights: extraQueries.isEmpty ? nil : extraQueries,
            additionalIdentifiers: metadata.identifiers,
            queryURLs: queryURLs,
            firstLinePatterns: metadata.firstLinePatterns
        )
    }

    private func validateNativeGrammarIfRequested(
        _ resolved: ResolvedGrammar,
        context: BuildContext,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> Bool {
        guard context.validatesNativeGrammar, let native = resolved.grammar.native else { return true }
        do {
            _ = try NativeGrammarLoader.shared.language(for: native)
            return true
        } catch let error as NativeGrammarLoadError {
            issues.append(.error(error.message, at: "\(location).grammar"))
        } catch {
            issues.append(.error(
                "Native grammar could not be loaded: \(error.localizedDescription)",
                at: "\(location).grammar"
            ))
        }
        return false
    }

    private func resolveGrammar(
        _ grammar: LanguageExtensionManifest.Contributes.Syntax.Grammar,
        context: BuildContext,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> ResolvedGrammar? {
        switch grammar.kind {
        case "builtin":
            return resolveBuiltInGrammar(grammar, base: context.base, location: location, into: &issues)
        case "native":
            guard context.nativeGrammarsEnabled else {
                issues.append(.error("Native grammars are disabled in Extensions settings.", at: "\(location).grammar"))
                return nil
            }
            return resolveNativeGrammar(
                grammar, pack: context.pack, consent: context.consent, location: location, into: &issues
            )
        default:
            issues.append(.error(
                "Grammar kind '\(grammar.kind)' cannot be loaded in this version of Nodal IDE.",
                at: "\(location).grammar"
            ))
            return nil
        }
    }

    private func resolveBuiltInGrammar(
        _ grammar: LanguageExtensionManifest.Contributes.Syntax.Grammar,
        base: LanguageCatalog,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> ResolvedGrammar? {
        let name = grammar.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            issues.append(.error("Built-in grammar requires `name`.", at: "\(location).grammar"))
            return nil
        }
        guard let language = base.language(forIdentifier: name),
              let builtIn = language.grammar.builtInLanguage else {
            issues.append(.error("Unknown built-in grammar '\(name)'.", at: "\(location).grammar"))
            return nil
        }
        return ResolvedGrammar(
            grammar: GrammarReference(identifier: builtIn.rawValue, builtInLanguage: builtIn),
            lineCommentString: language.lineCommentString,
            rangeCommentStrings: language.rangeCommentStrings,
            documentationCommentStrings: language.documentationCommentStrings
        )
    }

    private func resolveNativeGrammar(
        _ grammar: LanguageExtensionManifest.Contributes.Syntax.Grammar,
        pack: InstalledLanguageExtension,
        consent: NativeGrammarConsent,
        location: String,
        into issues: inout [LanguageExtensionIssue]
    ) -> ResolvedGrammar? {
        guard let path = grammar.path, let symbol = grammar.symbol else {
            issues.append(.error("Native grammar requires `path` and `symbol`.", at: "\(location).grammar"))
            return nil
        }
        guard let url = LanguageExtensionPaths.resolve(path, in: pack.root),
              LanguageExtensionPaths.isContained(url, in: pack.root) else {
            issues.append(.error("Native grammar escapes the pack: \(path)", at: "\(location).grammar"))
            return nil
        }
        guard let approved = consent.recordedHash(packID: pack.id, grammarPath: path) else {
            issues.append(.error(
                "Native grammar '\(symbol)' needs explicit consent before it can be loaded.",
                at: "\(location).grammar"
            ))
            return nil
        }
        let fileValues = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        guard fileValues?.isRegularFile == true else {
            issues.append(.error("Native grammar file is missing or is not a regular file.", at: "\(location).grammar"))
            return nil
        }
        let installedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let temporaryPath = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard !installedPath.hasPrefix(temporaryPath + "/") else {
            issues.append(.error(
                "Native grammar must be loaded from an installed location.", at: "\(location).grammar"
            ))
            return nil
        }
        if let declaredHash = grammar.sha256, declaredHash != approved {
            issues.append(.error(
                "Native grammar SHA-256 does not match the hash recorded when it was trusted.",
                at: "\(location).grammar.sha256"
            ))
            return nil
        }

        let name = symbol.hasPrefix("tree_sitter_") ? String(symbol.dropFirst("tree_sitter_".count)) : symbol
        let spec = NativeGrammarSpec(path: url, symbol: symbol, expectedSHA256: approved, packRoot: pack.root)
        return ResolvedGrammar(
            grammar: GrammarReference(native: spec, identifier: name),
            lineCommentString: "",
            rangeCommentStrings: ("", ""),
            documentationCommentStrings: []
        )
    }

    private func applyComments(
        _ comments: LanguageExtensionManifest.Contributes.Syntax.Comments?,
        to resolved: inout ResolvedGrammar
    ) {
        guard let comments else { return }
        if let line = comments.line {
            resolved.lineCommentString = line
        }
        if let block = comments.block, block.count == 2 {
            resolved.rangeCommentStrings = (block[0], block[1])
        }
    }

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
                    "\(name.capitalized) query escapes the pack: \(path)", at: "\(location).queries.\(name)"
                ))
                return nil
            }
            resolved.append((name: name, url: url))
        }
        return resolved
    }

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

    private func detectionExtensions(_ syntax: LanguageExtensionManifest.Contributes.Syntax) -> Set<String> {
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

    private func detectionIdentifiers(_ syntax: LanguageExtensionManifest.Contributes.Syntax) -> Set<String> {
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
