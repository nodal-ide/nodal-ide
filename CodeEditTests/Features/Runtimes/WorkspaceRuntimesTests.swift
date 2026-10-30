@testable import CodeEdit
import Foundation
import Testing

@Suite
struct WorkspaceRuntimesTests {
    @Test
    func legacyJsonDecodesIntoSelectionsDictionary() throws {
        let json = """
        {
            "php": { "version": "8.3.0" },
            "node": { "version": "20.10.0", "packageManager": "pnpm@9" }
        }
        """.data(using: .utf8)!

        let runtimes = try JSONDecoder().decode(WorkspaceRuntimes.self, from: json)

        #expect(runtimes.selection(for: .php).version == "8.3.0")
        #expect(runtimes.php.version == "8.3.0")
        #expect(runtimes.selection(for: .node).version == "20.10.0")
        #expect(runtimes.node.packageManager == "pnpm@9")
        #expect(!runtimes.isEmpty)
    }

    @Test
    func roundTripEncodingPreservesSelections() throws {
        var original = WorkspaceRuntimes()
        original.setSelection(RuntimeSelection(version: "8.2.1"), for: .php)
        original.setSelection(RuntimeSelection(version: "22.0.0", packageManager: "yarn@4"), for: .node)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceRuntimes.self, from: data)

        #expect(decoded.selection(for: .php).version == "8.2.1")
        #expect(decoded.selection(for: .node).version == "22.0.0")
        #expect(decoded.selection(for: .node).packageManager == "yarn@4")
    }

    @Test
    func emptyRuntimesReportsIsEmpty() {
        let empty = WorkspaceRuntimes()
        #expect(empty.isEmpty)

        var withPHP = WorkspaceRuntimes()
        withPHP.php = RuntimeSelection(version: "8.1.0")
        #expect(!withPHP.isEmpty)
    }

    @Test
    func mutatingPropertiesUpdatesDictionary() {
        var runtimes = WorkspaceRuntimes()
        runtimes.php = RuntimeSelection(version: "8.4.0")
        runtimes.node = RuntimeSelection(version: "20.0.0")

        #expect(runtimes.selections[.php]?.version == "8.4.0")
        #expect(runtimes.selections[.node]?.version == "20.0.0")
    }
}
