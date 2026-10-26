import Foundation
import XCTest
import CodeEditLang
@testable import CodeEdit

final class ReferencesFilterTests: XCTestCase {
    private func reference(
        _ preview: String,
        line: Int,
        container: String? = nil,
        heuristic: Bool = false
    ) -> EditorReference {
        EditorReference(
            fileURL: URL(fileURLWithPath: "/w/Models/User.php"),
            range: NSRange(location: line * 10, length: 4),
            line: line,
            column: 5,
            preview: preview,
            container: container,
            isHeuristic: heuristic
        )
    }

    private func group(_ path: String, _ references: [EditorReference]) -> ReferenceFileGroup {
        ReferenceFileGroup(
            fileURL: URL(fileURLWithPath: path),
            displayPath: path.replacingOccurrences(of: "/w/", with: ""),
            references: references
        )
    }

    private lazy var groups: [ReferenceFileGroup] = [
        group("/w/Models/User.php", [
            reference("public function name()", line: 10, container: "User"),
            reference("$this->name = $value", line: 22, container: "User", heuristic: true),
        ]),
        group("/w/Services/Billing.php", [
            reference("$user->name", line: 5, container: "Billing"),
        ]),
    ]

    func testEmptyQueryKeepsEverything() {
        let filtered = ReferencesFilter().groups(from: groups, currentFile: nil)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].count, 2)
        XCTAssertEqual(filtered[1].count, 1)
    }

    func testQueryMatchesPreviewCaseInsensitively() {
        var filter = ReferencesFilter()
        filter.query = "PUBLIC FUNCTION"

        let filtered = filter.groups(from: groups, currentFile: nil)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.references.count, 1)
        XCTAssertEqual(filtered.first?.references.first?.line, 10)
    }

    func testQueryMatchesContainerAndPath() {
        var byContainer = ReferencesFilter()
        byContainer.query = "billing"
        XCTAssertEqual(byContainer.groups(from: groups, currentFile: nil).first?.references.count, 1)

        var byPath = ReferencesFilter()
        byPath.query = "Services"
        XCTAssertEqual(byPath.groups(from: groups, currentFile: nil).count, 1)
    }

    func testQueryTrimsWhitespace() {
        var filter = ReferencesFilter()
        filter.query = "   name   "

        XCTAssertEqual(filter.groups(from: groups, currentFile: nil).count, 2)
    }

    func testNoMatchesProducesNoGroups() {
        var filter = ReferencesFilter()
        filter.query = "nothing-matches-this"

        XCTAssertTrue(filter.groups(from: groups, currentFile: nil).isEmpty)
    }

    func testCurrentFileGroupIsPinnedFirst() {
        let filtered = ReferencesFilter().groups(
            from: groups,
            currentFile: URL(fileURLWithPath: "/w/Services/Billing.php")
        )

        XCTAssertEqual(filtered.map(\.displayPath), ["Services/Billing.php", "Models/User.php"])
    }

    func testCurrentFileScope() {
        var filter = ReferencesFilter()
        filter.scope = .currentFile

        let filtered = filter.groups(
            from: groups,
            currentFile: URL(fileURLWithPath: "/w/Services/Billing.php")
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.displayPath, "Services/Billing.php")
    }

    func testCurrentFileScopeWithoutCurrentFileIsEmpty() {
        var filter = ReferencesFilter()
        filter.scope = .currentFile

        XCTAssertTrue(filter.groups(from: groups, currentFile: nil).isEmpty)
    }

    func testScopeAndQueryCombine() {
        var filter = ReferencesFilter()
        filter.scope = .currentFile
        filter.query = "this"

        let filtered = filter.groups(
            from: groups,
            currentFile: URL(fileURLWithPath: "/w/Models/User.php")
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.heuristicReferences.count, 1)
        XCTAssertEqual(filtered.first?.exactReferences.count, 0)
    }
}
