@testable import CodeEdit
import Testing

@Suite
struct AssistantMarkdownParserTests {
    @Test
    func parsesHeadingsParagraphsAndDividers() {
        let blocks = AssistantMarkdownParser.parse(
            """
            # Title

            First line
            second line.

            ---
            """
        )

        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line second line."),
            .divider
        ])
    }

    @Test
    func parsesBulletAndNumberedListsWithContinuations() {
        let blocks = AssistantMarkdownParser.parse(
            """
            Intro

            - one
              continued
            - two

            1. first
            2) second
            """
        )

        #expect(blocks == [
            .paragraph("Intro"),
            .bulletList(["one continued", "two"]),
            .numberedList(["first", "second"])
        ])
    }

    @Test
    func parsesClosedAndUnclosedCodeFences() {
        let closed = AssistantMarkdownParser.parse(
            """
            ```swift extra
            let value = 1
            ```
            """
        )
        #expect(closed == [
            .code(language: "swift", content: "let value = 1")
        ])

        let unclosed = AssistantMarkdownParser.parse(
            """
            ```swift
            let value = 1

            print(value)
            """
        )
        #expect(unclosed == [
            .code(language: "swift", content: "let value = 1\n\nprint(value)")
        ])
    }

    @Test
    func parsesQuotesAndTables() {
        let blocks = AssistantMarkdownParser.parse(
            """
            > first
            > second

            | Name | Count |
            | --- | ---: |
            | Alpha | 1 |
            | Beta |
            """
        )

        #expect(blocks == [
            .quote("first second"),
            .table(headers: ["Name", "Count"], rows: [["Alpha", "1"], ["Beta", ""]])
        ])
    }

    @Test
    func malformedMarkdownFallsBackToParagraphs() {
        let blocks = AssistantMarkdownParser.parse(
            """
            #Heading

            # Valid
            """
        )

        #expect(blocks == [
            .paragraph("#Heading"),
            .heading(level: 1, text: "Valid")
        ])
    }

    @Test
    func emptyInputProducesNoBlocks() {
        #expect(AssistantMarkdownParser.parse("") == [])
    }
}
