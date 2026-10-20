import Foundation
import Testing
@testable import CodeEdit

struct LogFileTailTests {
    private func write(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func returnsOnlyTheLastLines() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "app.log")
            try write((1...50).map { "line-\($0)" }, to: url)

            let tail = try LogFileTail.lines(at: url, maxLines: 3)

            #expect(tail == ["line-48", "line-49", "line-50"])
        }
    }

    @Test
    func boundsBytesReadAndDropsThePartialFirstLine() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "app.log")
            try write((1...2000).map { "line-\($0)" }, to: url)

            let tail = try LogFileTail.lines(at: url, maxLines: 500, maxBytes: 200)

            #expect(tail.count <= 500)
            #expect(tail.allSatisfy { $0.hasPrefix("line-") })
            #expect(tail.last == "line-2000")
        }
    }

    @Test
    func missingFileThrows() throws {
        try withTempDir { directory in
            #expect(throws: (any Error).self) {
                _ = try LogFileTail.lines(at: directory.appending(path: "missing.log"))
            }
        }
    }

    @Test
    func emptyFileReturnsNoLines() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "empty.log")
            try Data().write(to: url)

            #expect(try LogFileTail.lines(at: url).isEmpty)
        }
    }
}
