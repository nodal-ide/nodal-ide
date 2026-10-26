import Foundation
import XCTest
@testable import CodeEdit

@MainActor
final class ReferencesTargetCaptureTests: XCTestCase {
    private func offset(of needle: String, in text: String, delta: Int = 0) -> Int {
        (text as NSString).range(of: needle).location + delta
    }

    func testExpandsIdentifierAtCaret() {
        let text = "<?php\n$total = charge();"
        let caret = offset(of: "charge", in: text, delta: 2)
        let range = ReferencesTargetCapture.identifierRange(at: caret, in: text as NSString)

        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "charge")
    }

    func testCaretAfterIdentifierExpandsBack() {
        let text = "<?php charge();"
        let caret = offset(of: "charge", in: text) + "charge".count

        XCTAssertEqual(
            ReferencesTargetCapture.identifierRange(at: caret, in: text as NSString)
                .map { (text as NSString).substring(with: $0) },
            "charge"
        )
    }

    func testCaretOnPunctuationReturnsNil() {
        let text = "foo()"
        let caret = offset(of: ")", in: text)

        XCTAssertNil(ReferencesTargetCapture.identifierRange(at: caret, in: text as NSString))
    }

    func testVariablesAndQualifiedNamesAreSingleTokens() {
        let variable = "$amount"
        XCTAssertEqual(
            ReferencesTargetCapture.identifierRange(at: 2, in: variable as NSString)
                .map { (variable as NSString).substring(with: $0) },
            "$amount"
        )

        let qualified = "App\\Models\\User"
        XCTAssertEqual(
            ReferencesTargetCapture.identifierRange(at: 5, in: qualified as NSString)
                .map { (qualified as NSString).substring(with: $0) },
            "App\\Models\\User"
        )
    }

    func testEmptyTextHasNoIdentifier() {
        XCTAssertNil(ReferencesTargetCapture.identifierRange(at: 0, in: "" as NSString))
    }

    func testSelectionIsTrimmed() {
        let text = "call charge();"
        // Covers " charge", including the leading space but not the `(`.
        let selection = NSRange(location: 4, length: 7)

        let range = ReferencesTargetCapture.symbolRange(
            in: text as NSString,
            selections: [selection]
        )

        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "charge")
    }

    func testMultiLineSelectionFallsBackToIdentifierAtStart() {
        let text = "charge(\n  $amount\n);"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let range = ReferencesTargetCapture.symbolRange(
            in: text as NSString,
            selections: [selection]
        )

        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "charge")
    }

    func testWhitespaceSelectionReturnsNil() {
        let text = "a    b"
        let selection = NSRange(location: 1, length: 4)

        XCTAssertNil(ReferencesTargetCapture.symbolRange(in: text as NSString, selections: [selection]))
    }

    func testCaretBetweenTokensReturnsNil() {
        let text = "a + b"
        let caret = NSRange(location: 2, length: 0)

        XCTAssertNil(ReferencesTargetCapture.symbolRange(in: text as NSString, selections: [caret]))
    }

    func testCaretJustAfterWordResolvesThatWord() {
        let text = "a b"
        let caret = NSRange(location: 1, length: 0)

        XCTAssertEqual(
            ReferencesTargetCapture.symbolRange(in: text as NSString, selections: [caret])
                .map { (text as NSString).substring(with: $0) },
            "a"
        )
    }
}
