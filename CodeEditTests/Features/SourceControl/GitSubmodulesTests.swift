import Foundation
import Testing
@testable import CodeEdit

@Suite
struct GitSubmodulesTests {
    private let sha = String(repeating: "a", count: 40)

    @Test
    func parsesInitializedUninitializedAndConflictSubmodules() throws {
        let initialized = try #require(
            GitClient.parseSubmoduleStatusLine(" \(sha) vendor/lib (v1.2.3)")
        )
        #expect(initialized.path == "vendor/lib")
        #expect(initialized.sha == sha)
        #expect(initialized.state == .initialized)

        let uninitialized = try #require(
            GitClient.parseSubmoduleStatusLine("-\(sha) vendor/uninitialized")
        )
        #expect(uninitialized.state == .uninitialized)

        let conflict = try #require(
            GitClient.parseSubmoduleStatusLine("U\(sha) vendor/conflict")
        )
        #expect(conflict.state == .conflict)
    }

    @Test
    func preservesSpacesInSubmodulePaths() throws {
        let submodule = try #require(
            GitClient.parseSubmoduleStatusLine(" \(sha) path with spaces (heads/main)")
        )
        #expect(submodule.path == "path with spaces")
    }

    @Test
    func readsSubmoduleURLsFromGitmodules() async throws {
        try await withTempDir { directory in
            let shell = SubmoduleShellClient(sha: sha)
            let client = GitClient(directoryURL: directory, shellClient: shell)

            let submodules = try await client.listSubmodules()

            #expect(submodules.count == 1)
            #expect(submodules[0].path == "vendor/lib")
            #expect(submodules[0].url == "https://example.com/lib.git")
        }
    }
}

private final class SubmoduleShellClient: ShellClient {
    let sha: String

    init(sha: String) {
        self.sha = sha
    }

    override func run(_ args: String...) throws -> String {
        let command = args.joined(separator: " ")
        if command.contains("submodule status --recursive") {
            return " \(sha) vendor/lib (v1.0.0)\n"
        }
        if command.contains("config --file .gitmodules") {
            return "submodule.vendor/lib.path\nvendor/lib\0"
                + "submodule.vendor/lib.url\nhttps://example.com/lib.git\0"
        }
        return ""
    }
}
