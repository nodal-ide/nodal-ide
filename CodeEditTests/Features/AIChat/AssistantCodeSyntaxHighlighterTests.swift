@testable import CodeEdit
import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import Testing

@MainActor
@Suite
struct AssistantCodeSyntaxHighlighterTests {
    @Test
    func resolvesCommonFenceLabels() {
        #expect(AssistantCodeSyntaxHighlighter.language(for: "swift")?.id == .swift)
        #expect(AssistantCodeSyntaxHighlighter.language(for: "js")?.id == .javascript)
        #expect(AssistantCodeSyntaxHighlighter.language(for: "TypeScript")?.id == .typescript)
        #expect(AssistantCodeSyntaxHighlighter.language(for: ".py")?.id == .python)
        #expect(AssistantCodeSyntaxHighlighter.language(for: "text") == nil)
        #expect(AssistantCodeSyntaxHighlighter.language(for: "plaintext") == nil)
    }

    @Test
    func highlightsKnownCodeWithThemeAttributes() throws {
        let language = try #require(AssistantCodeSyntaxHighlighter.language(for: "swift"))
        #expect(language.language != nil)
        let text = EditorTheme.Attribute(color: .labelColor)
        let theme = EditorTheme(
            text: text,
            insertionPoint: .labelColor,
            invisibles: text,
            background: .textBackgroundColor,
            lineHighlight: .textBackgroundColor,
            selection: .selectedTextBackgroundColor,
            keywords: EditorTheme.Attribute(color: .systemPink),
            commands: EditorTheme.Attribute(color: .systemBlue),
            types: EditorTheme.Attribute(color: .systemTeal),
            attributes: EditorTheme.Attribute(color: .systemOrange),
            variables: EditorTheme.Attribute(color: .labelColor),
            values: EditorTheme.Attribute(color: .systemPurple),
            numbers: EditorTheme.Attribute(color: .systemGreen),
            strings: EditorTheme.Attribute(color: .systemRed),
            characters: EditorTheme.Attribute(color: .systemRed),
            comments: EditorTheme.Attribute(color: .secondaryLabelColor)
        )

        let highlighted = try #require(
            AssistantCodeSyntaxHighlighter.highlight(
                "let value = 42\nprint(\"hello\")",
                language: language,
                theme: theme,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular)
            )
        )

        #expect(String(highlighted.characters) == "let value = 42\nprint(\"hello\")")
        #expect(highlighted.runs.count > 1)
    }
}
