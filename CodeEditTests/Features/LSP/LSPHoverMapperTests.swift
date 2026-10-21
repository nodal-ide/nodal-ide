import XCTest
import LanguageServerProtocol
import CodeEditSourceEditor
@testable import CodeEdit

final class LSPHoverMapperTests: XCTestCase {
    func testPreservesMarkdownMarkupContent() throws {
        let value = """
        **Payment**

        ```swift
        let amount = 100
        ```
        """
        let content = try XCTUnwrap(
            LSPHoverMapper.content(.optionC(MarkupContent(kind: .markdown, value: value)))
        )

        guard case .markdown(let markdown) = content else {
            return XCTFail("Expected Markdown")
        }
        XCTAssertEqual(markdown, value)
    }

    func testPreservesPlaintextMarkupContent() throws {
        let content = try XCTUnwrap(
            LSPHoverMapper.content(.optionC(MarkupContent(kind: .plaintext, value: "Line one\n\nLine two")))
        )

        guard case .plainText(let text) = content else {
            return XCTFail("Expected plain text")
        }
        XCTAssertEqual(text, "Line one\n\nLine two")
    }

    func testTreatsBareMarkedStringAsMarkdown() throws {
        let content = try XCTUnwrap(
            LSPHoverMapper.content(.optionA(.optionA("**Bold** and `code`")))
        )

        guard case .markdown(let markdown) = content else {
            return XCTFail("Expected Markdown")
        }
        XCTAssertEqual(markdown, "**Bold** and `code`")
    }

    func testLanguageTaggedMarkedStringBecomesCodeBlock() throws {
        let pair = LanguageStringPair(language: .typescript, value: "const amount = 100;")
        let content = try XCTUnwrap(
            LSPHoverMapper.content(.optionA(.optionB(pair)))
        )

        guard case .document(let document) = content,
              case .code(let code) = document.blocks.first else {
            return XCTFail("Expected a code block document")
        }
        XCTAssertEqual(code.text, "const amount = 100;")
        XCTAssertEqual(code.language, "typescript")
    }

    func testMarkedStringArrayPreservesOrder() throws {
        let contents: [MarkedString] = [
            .optionA("**Payment**"),
            .optionB(LanguageStringPair(language: .swift, value: "func charge()")),
        ]
        let content = try XCTUnwrap(LSPHoverMapper.content(.optionB(contents)))

        guard case .document(let document) = content else {
            return XCTFail("Expected a document")
        }
        XCTAssertEqual(document.blocks.count, 2)
        guard case .markdown(let markdown) = document.blocks[0],
              case .code(let code) = document.blocks[1] else {
            return XCTFail("Expected Markdown followed by code")
        }
        XCTAssertEqual(markdown, "**Payment**")
        XCTAssertEqual(code.text, "func charge()")
        XCTAssertEqual(code.language, "swift")
    }

    func testAdvertisesMarkdownHoverSupport() async throws {
        let provider = LanguageServer<CodeFileDocument>.getInitParams(workspacePath: "/tmp")
        let params = try await provider()

        XCTAssertEqual(params.capabilities.textDocument?.hover?.contentFormat, [.markdown, .plaintext])
    }

    func testDropsEmptyContent() {
        XCTAssertNil(LSPHoverMapper.content(.optionB([])))
        XCTAssertNil(LSPHoverMapper.content(.optionC(MarkupContent(kind: .markdown, value: " \n "))))
        XCTAssertNil(LSPHoverMapper.content(.optionC(MarkupContent(kind: .plaintext, value: ""))))
    }
}
