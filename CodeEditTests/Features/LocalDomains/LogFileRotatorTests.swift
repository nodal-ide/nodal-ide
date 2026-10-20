import Foundation
import Testing
@testable import CodeEdit

struct LogFileRotatorTests {
    private func write(_ bytes: Int, to url: URL) throws {
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    @Test
    func doesNothingBelowTheThreshold() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "app.log")
            try write(100, to: url)

            let rotated = try LogFileRotator.rotateIfNeeded(url, maxBytes: 1024)

            #expect(!rotated)
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    @Test
    func renamesTheActiveFileAside() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "app.log")
            try write(2048, to: url)
            let path = url.path(percentEncoded: false)

            let rotated = try LogFileRotator.rotateIfNeeded(url, maxBytes: 1024)

            #expect(rotated)
            #expect(!FileManager.default.fileExists(atPath: path))
            #expect(FileManager.default.fileExists(atPath: "\(path).1"))
        }
    }

    @Test
    func shiftsBackupsAndKeepsOnlyTheConfiguredCount() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "app.log")
            let path = url.path(percentEncoded: false)

            for _ in 0..<4 {
                try write(2048, to: url)
                _ = try LogFileRotator.rotateIfNeeded(url, maxBytes: 1024, keep: 2)
            }

            #expect(FileManager.default.fileExists(atPath: "\(path).1"))
            #expect(FileManager.default.fileExists(atPath: "\(path).2"))
            #expect(!FileManager.default.fileExists(atPath: "\(path).3"))
        }
    }
}
