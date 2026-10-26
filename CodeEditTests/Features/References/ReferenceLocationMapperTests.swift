import Foundation
import XCTest
import CodeEditLang
@testable import CodeEdit

final class ReferenceLocationMapperTests: XCTestCase {
    private final class CountingTextProvider: SourceTextProviding, @unchecked Sendable {
        private let texts: [String: String]
        private let lock = NSLock()
        private var readPaths: [String] = []

        init(_ texts: [String: String]) {
            self.texts = texts
        }

        var reads: [String] {
            lock.lock()
            defer { lock.unlock() }
            return readPaths
        }

        func text(for url: URL) -> String? {
            lock.lock()
            readPaths.append(url.path)
            lock.unlock()
            return texts[url.path]
        }
    }

    private func location(
        _ uri: String,
        _ line: Int,
        _ character: Int,
        length: Int = 3
    ) -> ReferenceLocationMapper.LocationRef {
        ReferenceLocationMapper.LocationRef(
            uri: uri,
            startLine: line,
            startCharacter: character,
            endLine: line,
            endCharacter: character + length
        )
    }

    func testMapsLocationsAndReadsEachFileOnce() {
        let provider = CountingTextProvider([
            "/w/a.php": "<?php\nfoo();\nbar();",
            "/w/b.php": "<?php\nfoo();",
        ])
        let locations = [
            location("file:///w/a.php", 1, 0),
            location("file:///w/a.php", 2, 0),
            location("file:///w/b.php", 1, 0),
        ]

        let outcome = ReferenceLocationMapper.outcome(for: locations, textProvider: provider, limit: 100)

        XCTAssertEqual(outcome.references?.count, 3)
        XCTAssertTrue(outcome.isComplete)
        XCTAssertEqual(provider.reads.sorted(), ["/w/a.php", "/w/b.php"])
        XCTAssertEqual(outcome.references?.map(\.line), [2, 3, 2])
        XCTAssertEqual(outcome.references?.map(\.preview), ["foo();", "bar();", "foo();"])
    }

    func testEmptyLocationsAreAnAuthoritativeEmptyResult() {
        let provider = CountingTextProvider([:])

        let outcome = ReferenceLocationMapper.outcome(for: [], textProvider: provider, limit: 100)

        XCTAssertEqual(outcome, .results([], isComplete: true))
        XCTAssertEqual(provider.reads, [])
    }

    func testDuplicateLocationsAreDeduped() {
        let provider = CountingTextProvider(["/w/a.php": "<?php\nfoo();"])
        let duplicate = location("file:///w/a.php", 1, 0)

        let outcome = ReferenceLocationMapper.outcome(
            for: [duplicate, duplicate],
            textProvider: provider,
            limit: 100
        )

        XCTAssertEqual(outcome.references?.count, 1)
    }

    func testLimitTruncatesAndClearsCompleteness() {
        let provider = CountingTextProvider(["/w/a.php": "<?php\nfoo();\nbar();"])
        let locations = [
            location("file:///w/a.php", 1, 0),
            location("file:///w/a.php", 2, 0),
        ]

        let outcome = ReferenceLocationMapper.outcome(for: locations, textProvider: provider, limit: 1)

        XCTAssertEqual(outcome.references?.count, 1)
        XCTAssertFalse(outcome.isComplete)
    }

    func testUnreadableFileMarksResultIncomplete() {
        let provider = CountingTextProvider(["/w/a.php": "<?php\nfoo();"])
        let locations = [
            location("file:///w/a.php", 1, 0),
            location("file:///w/missing.php", 1, 0),
        ]

        let outcome = ReferenceLocationMapper.outcome(for: locations, textProvider: provider, limit: 100)

        XCTAssertEqual(outcome.references?.count, 1)
        XCTAssertFalse(outcome.isComplete)
    }

    func testNonFileURIIsSkipped() {
        let provider = CountingTextProvider(["/w/a.php": "<?php\nfoo();"])
        let locations = [
            location("untitled:Untitled-1", 0, 0),
            location("file:///w/a.php", 1, 0),
        ]

        let outcome = ReferenceLocationMapper.outcome(for: locations, textProvider: provider, limit: 100)

        XCTAssertEqual(outcome.references?.count, 1)
        XCTAssertTrue(outcome.isComplete)
    }

    func testOutOfRangeLineIsSkipped() {
        let provider = CountingTextProvider(["/w/a.php": "<?php\nfoo();"])

        let outcome = ReferenceLocationMapper.outcome(
            for: [location("file:///w/a.php", 99, 0)],
            textProvider: provider,
            limit: 100
        )

        XCTAssertEqual(outcome.references?.count, 0)
        XCTAssertTrue(outcome.isComplete)
    }

    func testLSPPositionForOffset() {
        XCTAssertEqual(ReferenceLocationMapper.position(forOffset: 5, in: "abc\ndef")?.line, 1)
        XCTAssertEqual(ReferenceLocationMapper.position(forOffset: 5, in: "abc\ndef")?.character, 1)
        XCTAssertNil(ReferenceLocationMapper.position(forOffset: -1, in: "abc"))
    }
}

final class ReferenceFileGroupTests: XCTestCase {
    private func reference(_ path: String, line: Int, heuristic: Bool = false) -> EditorReference {
        EditorReference(
            fileURL: URL(fileURLWithPath: path),
            range: NSRange(location: line * 10, length: 3),
            line: line,
            column: 1,
            preview: "preview",
            isHeuristic: heuristic
        )
    }

    func testGroupsByFileAndUsesRelativePaths() {
        let references = [
            reference("/w/Models/B.php", line: 3),
            reference("/w/App/A.php", line: 2),
            reference("/w/App/A.php", line: 1),
        ]

        let groups = ReferenceFileGroup.group(references, root: URL(fileURLWithPath: "/w"))

        XCTAssertEqual(groups.map(\.displayPath), ["App/A.php", "Models/B.php"])
        XCTAssertEqual(groups[0].references.map(\.line), [1, 2])
        XCTAssertEqual(groups[0].count, 2)
    }

    func testSplitsExactAndHeuristicReferences() {
        let group = ReferenceFileGroup(
            fileURL: URL(fileURLWithPath: "/w/a.php"),
            displayPath: "a.php",
            references: [
                reference("/w/a.php", line: 1),
                reference("/w/a.php", line: 2, heuristic: true),
            ]
        )

        XCTAssertEqual(group.exactReferences.count, 1)
        XCTAssertEqual(group.heuristicReferences.count, 1)
        XCTAssertEqual(group.count, 2)
    }

    func testOutsideRootKeepsAbsolutePath() {
        let groups = ReferenceFileGroup.group(
            [reference("/elsewhere/a.php", line: 1)],
            root: URL(fileURLWithPath: "/w")
        )

        XCTAssertEqual(groups.first?.displayPath, "/elsewhere/a.php")
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(ReferenceFileGroup.group([], root: URL(fileURLWithPath: "/w")).isEmpty)
    }
}
