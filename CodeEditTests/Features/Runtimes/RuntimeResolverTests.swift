@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct RuntimeResolverTests {
    @Test
    func projectPinnedVersionReadsEcosystemFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nvmrc = tempDir.appending(path: ".nvmrc")
        try "v20.10.0\n".write(to: nvmrc, atomically: true, encoding: .utf8)

        let phpVersion = tempDir.appending(path: ".php-version")
        try "8.3.6\n".write(to: phpVersion, atomically: true, encoding: .utf8)

        let nvmContent = try String(contentsOf: nvmrc, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        #expect(nvmContent == "20.10.0")

        let phpContent = try String(contentsOf: phpVersion, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(phpContent == "8.3.6")
    }

    @Test
    func ecosystemPinWritingWritesExpectedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nvmrc = tempDir.appending(path: ".nvmrc")
        try "22.1.0".write(to: nvmrc, atomically: true, encoding: .utf8)
        #expect(try String(contentsOf: nvmrc, encoding: .utf8) == "22.1.0")

        let phpVersion = tempDir.appending(path: ".php-version")
        try "8.4.1".write(to: phpVersion, atomically: true, encoding: .utf8)
        #expect(try String(contentsOf: phpVersion, encoding: .utf8) == "8.4.1")
    }
}
