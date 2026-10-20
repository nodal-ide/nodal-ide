import Foundation
import Testing
@testable import CodeEdit

@Suite
struct GitRepositoryScannerTests {
    @Test
    func discoversRootAndSubmodulesInsideWorkspace() async throws {
        try await withTempDir { directory in
            let shell = ScannerShellClient(
                gitRoot: directory,
                submodulePaths: ["Packages/Alpha", "vendor/lib with space"]
            )

            let repositories = await GitRepositoryScanner().scan(
                workspaceURL: directory,
                shellClient: shell
            )

            let expectedRoots = [
                directory,
                directory.appending(path: "Packages/Alpha"),
                directory.appending(path: "vendor/lib with space")
            ].map(\.standardizedFileURL)

            #expect(repositories.count == expectedRoots.count)
            #expect(zip(repositories, expectedRoots).allSatisfy { $0.rootURL.componentCompare($1) })
            #expect(repositories[0].isSubmodule == false)
            #expect(repositories[0].parentRootURL == nil)
            #expect(repositories[1].isSubmodule)
            #expect(repositories[1].parentRootURL?.componentCompare(directory.standardizedFileURL) == true)
        }
    }

    @Test
    func discoversIndependentRepositoriesWhenWorkspaceIsNotGitRoot() async throws {
        try await withTempDir { directory in
            let shell = ScannerShellClient(
                gitRoot: nil,
                submodulePaths: [],
                independentRootPaths: [
                    "./codeedit-deps/Alpha/.git",
                    "./CodeEdit/.git",
                    "./codeedit-deps/zeta/.git"
                ]
            )

            let repositories = await GitRepositoryScanner().scan(
                workspaceURL: directory,
                shellClient: shell
            )

            let expectedRoots = [
                directory.appending(path: "CodeEdit"),
                directory.appending(path: "codeedit-deps/Alpha"),
                directory.appending(path: "codeedit-deps/zeta")
            ].map(\.standardizedFileURL)

            #expect(repositories.count == expectedRoots.count)
            #expect(zip(repositories, expectedRoots).allSatisfy { $0.rootURL.componentCompare($1) })
            #expect(repositories.allSatisfy { !$0.isSubmodule })
            #expect(repositories.allSatisfy { $0.parentRootURL == nil })
        }
    }

    @Test
    func ignoresSubmodulesOutsideWorkspaceAndSiblingPrefixes() async throws {
        try await withTempDir { directory in
            let shell = ScannerShellClient(
                gitRoot: directory,
                submodulePaths: ["../\(directory.lastPathComponent)-other/vendor", "vendor/inside"]
            )

            let repositories = await GitRepositoryScanner().scan(
                workspaceURL: directory,
                shellClient: shell
            )

            #expect(repositories.count == 2)
            #expect(repositories[1].rootURL.componentCompare(
                directory.appending(path: "vendor/inside").standardizedFileURL
            ))
        }
    }

    @Test
    func sortsSubmodulesByDepthThenPath() async throws {
        try await withTempDir { directory in
            let shell = ScannerShellClient(
                gitRoot: directory,
                submodulePaths: ["vendor/zeta", "Packages/Alpha", "vendor/alpha"]
            )

            let repositories = await GitRepositoryScanner().scan(
                workspaceURL: directory,
                shellClient: shell
            )

            #expect(repositories.map(\.rootURL.lastPathComponent) == [
                directory.lastPathComponent,
                "Alpha",
                "alpha",
                "zeta"
            ])
        }
    }

    @Test
    func assignsImmediateParentToNestedSubmodules() async throws {
        try await withTempDir { directory in
            let shell = ScannerShellClient(
                gitRoot: directory,
                submodulePaths: ["outer", "outer/nested", "other"]
            )

            let repositories = await GitRepositoryScanner().scan(
                workspaceURL: directory,
                shellClient: shell
            )

            let byName = Dictionary(uniqueKeysWithValues: repositories.map {
                ($0.rootURL.lastPathComponent, $0)
            })
            #expect(byName["outer"]?.parentRootURL?.componentCompare(directory.standardizedFileURL) == true)
            #expect(byName["nested"]?.parentRootURL?.componentCompare(
                directory.appending(path: "outer").standardizedFileURL
            ) == true)
            #expect(byName["other"]?.parentRootURL?.componentCompare(directory.standardizedFileURL) == true)
        }
    }
}

private final class ScannerShellClient: ShellClient {
    let gitRoot: URL?
    let submodulePaths: [String]
    let independentRootPaths: [String]

    init(
        gitRoot: URL?,
        submodulePaths: [String],
        independentRootPaths: [String] = []
    ) {
        self.gitRoot = gitRoot
        self.submodulePaths = submodulePaths
        self.independentRootPaths = independentRootPaths
    }

    override func run(_ args: String...) throws -> String {
        let command = args.joined(separator: " ")
        if command.contains("rev-parse --show-toplevel") {
            guard let gitRoot else {
                return "fatal: not a git repository (or any of the parent directories): .git\n"
            }
            return "\(gitRoot.path(percentEncoded: false))\n"
        }
        if command.contains("submodule foreach") {
            return submodulePaths.joined(separator: "\n") + (submodulePaths.isEmpty ? "" : "\n")
        }
        if command.contains("find .") {
            return independentRootPaths.joined(separator: "\n")
                + (independentRootPaths.isEmpty ? "" : "\n")
        }
        return ""
    }
}
