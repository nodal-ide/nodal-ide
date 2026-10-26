import Foundation
import XCTest
import CodeEditLang
@testable import CodeEdit

@MainActor
final class ReferencesSessionTests: XCTestCase {
    private final class StubProvider: ReferenceProviding {
        var supportsReferences: Bool { true }

        private let handler: (ReferenceQuery) async -> ReferenceQueryOutcome

        init(_ handler: @escaping (ReferenceQuery) async -> ReferenceQueryOutcome) {
            self.handler = handler
        }

        func references(for query: ReferenceQuery) async -> ReferenceQueryOutcome {
            await handler(query)
        }
    }

    private func query(_ identifier: String = "foo") -> ReferenceQuery {
        ReferenceQuery(
            target: ReferenceTarget(
                identifier: identifier,
                fileURL: URL(fileURLWithPath: "/w/a.php"),
                range: NSRange(location: 6, length: 3)
            ),
            languageID: "php",
            source: "<?php foo();",
            workspaceRoot: URL(fileURLWithPath: "/w")
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testAppliesResults() async {
        let session = ReferencesSession(providerOverride: { _ in
            StubProvider { _ in .results([referencesTestReference()], isComplete: true) }
        })

        session.run(query())
        await waitUntil { session.phase == .results }

        XCTAssertEqual(session.totalCount, 1)
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.target?.identifier, "foo")
        XCTAssertEqual(session.references(for: URL(fileURLWithPath: "/w/a.php")).count, 1)
    }

    func testPartialResultsStayIncomplete() async {
        let session = ReferencesSession(providerOverride: { _ in
            StubProvider { _ in .results([referencesTestReference()], isComplete: false) }
        })

        session.run(query())
        await waitUntil { session.phase == .results }

        XCTAssertFalse(session.isComplete)
    }

    func testFailureIsSurfaced() async {
        let session = ReferencesSession(providerOverride: { _ in
            StubProvider { _ in .failed(.transport("socket closed")) }
        })

        session.run(query())
        await waitUntil { session.phase == .failed(.transport("socket closed")) }

        XCTAssertEqual(session.phase, .failed(.transport("socket closed")))
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertFalse(session.isComplete)
    }

    func testUnsupportedIsSurfaced() async {
        let session = ReferencesSession(providerOverride: { _ in
            StubProvider { _ in .unsupported(reason: "Not a symbol") }
        })

        session.run(query())
        await waitUntil { session.phase == .unsupported("Not a symbol") }

        XCTAssertEqual(session.phase, .unsupported("Not a symbol"))
        XCTAssertTrue(session.isComplete)
    }

    func testMissingProviderIsUnsupported() {
        let session = ReferencesSession(providerOverride: { _ in nil })

        session.run(query())

        guard case .unsupported(let reason) = session.phase else {
            return XCTFail("expected unsupported, got \(session.phase)")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testTimeoutFailsTheQuery() async {
        let session = ReferencesSession(
            providerOverride: { _ in
                StubProvider { _ in
                    try? await Task.sleep(for: .seconds(1))
                    return .results([EditorReference(
                        fileURL: URL(fileURLWithPath: "/w/a.php"),
                        range: NSRange(location: 0, length: 3),
                        line: 1,
                        column: 1,
                        preview: "foo"
                    )], isComplete: true)
                }
            },
            timeout: 0.05
        )

        session.run(query())
        await waitUntil { session.phase == .failed(.timedOut) }

        XCTAssertEqual(session.phase, .failed(.timedOut))
        XCTAssertTrue(session.groups.isEmpty)
    }

    func testSupersededQueryIsDiscarded() async {
        let provider = StubProvider { query in
            if query.target.identifier == "slow" {
                try? await Task.sleep(for: .milliseconds(150))
                return .results([EditorReference(
                    fileURL: URL(fileURLWithPath: "/w/slow.php"),
                    range: NSRange(location: 0, length: 3),
                    line: 1,
                    column: 1,
                    preview: "slow"
                )], isComplete: true)
            }
            return .results([EditorReference(
                fileURL: URL(fileURLWithPath: "/w/fast.php"),
                range: NSRange(location: 0, length: 3),
                line: 1,
                column: 1,
                preview: "fast"
            )], isComplete: true)
        }
        let session = ReferencesSession(providerOverride: { _ in provider })

        session.run(query("slow"))
        session.run(query("fast"))
        await waitUntil { session.phase == .results }
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(session.target?.identifier, "fast")
        XCTAssertEqual(session.groups.first?.fileURL.lastPathComponent, "fast.php")
    }

    func testClearResetsState() async {
        let session = ReferencesSession(providerOverride: { _ in
            StubProvider { _ in .results([referencesTestReference()], isComplete: true) }
        })

        session.run(query())
        await waitUntil { session.phase == .results }

        session.clear()

        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertEqual(session.totalCount, 0)
        XCTAssertNil(session.target)
    }
}

private func referencesTestReference(_ path: String = "/w/a.php", line: Int = 1) -> EditorReference {
    EditorReference(
        fileURL: URL(fileURLWithPath: path),
        range: NSRange(location: 6, length: 3),
        line: line,
        column: 7,
        preview: "foo();"
    )
}
