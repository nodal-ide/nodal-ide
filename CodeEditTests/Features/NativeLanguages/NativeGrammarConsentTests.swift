@testable import CodeEdit
import Testing
import Foundation
import CryptoKit
import CodeEditLang
import CodeEditLanguages

@Suite
struct NativeGrammarConsentTests {
    @Test
    func extensionSyntaxFeatureFlagsDefaultOnForExistingSettings() throws {
        let settings = try JSONDecoder().decode(SettingsData.ExtensionsSettings.self, from: Data("{}".utf8))

        #expect(settings.syntaxPacksEnabled)
        #expect(settings.nativeGrammarsEnabled)
    }

    @Test
    func consentIsRecordedPerPackAndGrammarPath() {
        var consent = NativeGrammarConsent()
        consent.recorded[NativeGrammarConsent.key(packID: "com.example.a", grammarPath: "grammars/a.dylib")] = "abc"

        #expect(consent.recordedHash(packID: "com.example.a", grammarPath: "grammars/a.dylib") == "abc")
        #expect(consent.recordedHash(packID: "com.example.b", grammarPath: "grammars/a.dylib") == nil)
        #expect(consent.recordedHash(packID: "com.example.a", grammarPath: "grammars/b.dylib") == nil)
    }

    @Test
    func declarationsListOnlyNativeGrammars() throws {
        try withTempDir { directory in
            let pack = makePack(root: directory, syntax: [nativeSyntax, builtInSyntax])
            let declarations = NativeGrammarConsent.declarations(in: pack)

            #expect(declarations.count == 1)
            #expect(declarations.first?.path == "grammars/lib.dylib")
            #expect(declarations.first?.symbol == "tree_sitter_svelte")
        }
    }

    @Test
    func fileHashMatchesTheContentsOnDisk() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "grammar.dylib")
            let contents = Data([0x01, 0x02, 0x03, 0x04])
            try contents.write(to: url)

            let expected = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
            #expect(NativeGrammarConsent.hashOfFile(at: url) == expected)
            #expect(NativeGrammarConsent.hashOfFile(at: directory.appending(path: "missing.dylib")) == nil)
        }
    }

    @Test
    func untrustedNativeGrammarContributesNothing() throws {
        try withTempDir { directory in
            try write("(comment) @comment\n", to: "queries/highlights.scm", in: directory)
            try write("", to: "grammars/lib.dylib", in: directory)

            let outcome = SyntaxContributionLoader()
                .load([makePack(root: directory, syntax: [nativeSyntax])], base: .builtIn, consent: .none)[0]

            #expect(outcome.languages.isEmpty)
            #expect(outcome.issues.contains {
                $0.severity == .error && $0.message.contains("explicit consent")
            })
        }
    }

    @Test
    func malformedHighlightsQueryIsRejected() throws {
        try withTempDir { directory in
            try write("(not-a-valid-query", to: "queries/highlights.scm", in: directory)

            let outcome = SyntaxContributionLoader()
                .load([makePack(root: directory, syntax: [builtInSyntax])], base: .builtIn, consent: .none)[0]

            #expect(outcome.languages.isEmpty)
            #expect(outcome.issues.contains {
                $0.severity == .error && $0.message.contains("Highlights query failed to compile")
            })
            #expect(SyntaxContributionLoader.catalog(base: .builtIn, outcomes: [outcome]).languages.count ==
                LanguageCatalog.builtIn.languages.count)
        }
    }

    @Test
    func commentTokensOverrideTheBuiltInGrammar() throws {
        try withTempDir { directory in
            try write("(comment) @comment\n", to: "queries/highlights.scm", in: directory)

            var syntax = builtInSyntax
            syntax.comments = .init(line: "//", block: ["/*", "*/"])
            let outcome = SyntaxContributionLoader()
                .load([makePack(root: directory, syntax: [syntax])], base: .builtIn, consent: .none)[0]

            #expect(outcome.languages.count == 1)
            #expect(outcome.languages.first?.lineCommentString == "//")
            #expect(outcome.languages.first?.rangeCommentStrings.0 == "/*")
            #expect(outcome.languages.first?.rangeCommentStrings.1 == "*/")
        }
    }

    @Test
    func trustedNativeGrammarInTemporaryLocationIsRejected() throws {
        try withTempDir { directory in
            try write("(comment) @comment\n", to: "queries/highlights.scm", in: directory)
            try write("", to: "grammars/lib.dylib", in: directory)

            var consent = NativeGrammarConsent()
            let key = NativeGrammarConsent.key(
                packID: "com.example.svelte",
                grammarPath: "grammars/lib.dylib"
            )
            consent.recorded[key] =
                NativeGrammarConsent.hashOfFile(at: directory.appending(path: "grammars/lib.dylib")) ?? "missing"

            let outcome = SyntaxContributionLoader()
                .load([makePack(root: directory, syntax: [nativeSyntax])], base: .builtIn, consent: consent)[0]

            #expect(outcome.languages.isEmpty)
            #expect(outcome.issues.contains {
                $0.severity == .error && $0.message.contains("installed location")
            })
        }
    }

    @Test
    func workspacePacksCannotDeclareNativeGrammars() throws {
        try withTempDir { directory in
            try write("(comment) @comment\n", to: "queries/highlights.scm", in: directory)
            try write("", to: "grammars/lib.dylib", in: directory)

            let pack = makePack(root: directory, syntax: [nativeSyntax], scope: .workspace)
            let outcome = SyntaxContributionLoader()
                .load([pack], base: .builtIn, consent: .none)[0]

            #expect(outcome.languages.isEmpty)
            #expect(outcome.issues.contains {
                $0.severity == .error && $0.message.contains("globally installed extensions")
            })
        }
    }

    @Test
    func disabledNativeGrammarFeatureRejectsPackWithoutLoadingIt() throws {
        try withTempDir { directory in
            try write("(comment) @comment\n", to: "queries/highlights.scm", in: directory)
            try write("", to: "grammars/lib.dylib", in: directory)

            let outcome = SyntaxContributionLoader().load(
                [makePack(root: directory, syntax: [nativeSyntax])],
                base: .builtIn,
                consent: .none,
                nativeGrammarsEnabled: false
            )[0]

            #expect(outcome.languages.isEmpty)
            #expect(outcome.issues.contains {
                $0.severity == .error && $0.message.contains("Native grammars are disabled")
            })
        }
    }

    // MARK: - Helpers

    private var nativeSyntax: LanguageExtensionManifest.Contributes.Syntax {
        .init(
            id: "svelte",
            displayName: "Svelte",
            extensions: ["svelte"],
            grammar: .init(kind: "native", path: "grammars/lib.dylib", symbol: "tree_sitter_svelte"),
            queries: .init(highlights: "queries/highlights.scm")
        )
    }

    private var builtInSyntax: LanguageExtensionManifest.Contributes.Syntax {
        .init(
            id: "geojson",
            displayName: "GeoJSON",
            extensions: ["geojson"],
            grammar: .init(kind: "builtin", name: "json"),
            queries: .init(highlights: "queries/highlights.scm")
        )
    }

    private func makePack(
        root: URL,
        syntax: [LanguageExtensionManifest.Contributes.Syntax],
        scope: LanguageExtensionPackScope = .global
    ) -> InstalledLanguageExtension {
        let manifest = LanguageExtensionManifest(
            schemaVersion: 2,
            id: "com.example.svelte",
            name: "Svelte",
            version: "1.0.0",
            type: "nativeSyntaxPack",
            capabilities: ["syntax", "nativeGrammars"],
            contributes: .init(syntax: syntax)
        )
        return InstalledLanguageExtension(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            root: root,
            manifest: manifest,
            scope: scope
        )
    }

    private func write(_ contents: String, to relativePath: String, in root: URL) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
