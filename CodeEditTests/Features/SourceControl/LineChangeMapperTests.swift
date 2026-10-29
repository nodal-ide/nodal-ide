//
//  LineChangeMapperTests.swift
//  CodeEditTests
//

import CodeEditSourceEditor
import Testing
@testable import CodeEdit

@Suite
struct LineChangeMapperTests {
    private func changes(_ diff: String) -> [LineChange] {
        LineChangeMapper.changes(from: DiffParser.parse(diff))
    }

    @Test
    func newFileIsEntirelyAdded() {
        let diff = """
        --- /dev/null
        +++ b/a.txt
        @@ -0,0 +1,3 @@
        +one
        +two
        +three
        """
        #expect(changes(diff) == [LineChange(kind: .added, lines: 1...3)])
    }

    @Test
    func replacementIsModified() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -2 +2 @@
        -old
        +new
        """
        #expect(changes(diff) == [LineChange(kind: .modified, lines: 2...2)])
    }

    @Test
    func insertionInMiddleIsAdded() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -4,0 +5,2 @@
        +first
        +second
        """
        #expect(changes(diff) == [LineChange(kind: .added, lines: 5...6)])
    }

    @Test
    func deletionOnlyIsMarker() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -5,2 +4,0 @@
        -gone
        -gone too
        """
        #expect(changes(diff) == [LineChange(kind: .deleted, lines: 4...4)])
    }

    @Test
    func deletionAtStartOfFileClampsToFirstLine() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -1,2 +0,0 @@
        -gone
        -gone too
        """
        #expect(changes(diff) == [LineChange(kind: .deleted, lines: 1...1)])
    }

    @Test
    func largerDeletionAddsMarkerAlongsideReplacement() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -10,3 +10,1 @@
        -a
        -b
        -c
        +x
        """
        #expect(changes(diff) == [
            LineChange(kind: .modified, lines: 10...10),
            LineChange(kind: .deleted, lines: 10...10)
        ])
    }

    @Test
    func adjacentHunksAreCoalesced() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -2,0 +3,1 @@
        +a
        @@ -2,0 +4,1 @@
        +b
        @@ -2,0 +9,1 @@
        +c
        """
        #expect(changes(diff) == [
            LineChange(kind: .added, lines: 3...4),
            LineChange(kind: .added, lines: 9...9)
        ])
    }

    @Test
    func emptyDiffHasNoChanges() {
        #expect(changes("").isEmpty)
    }

    @Test
    func insertionAtEndOfFile() {
        let diff = """
        --- a/a.txt
        +++ b/a.txt
        @@ -20,0 +21,1 @@
        +tail
        """
        #expect(changes(diff) == [LineChange(kind: .added, lines: 21...21)])
    }
}
