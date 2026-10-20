import Foundation
import Testing
@testable import CodeEdit

@MainActor
@Suite
struct SourceControlCoordinatorTests {
    @Test
    func repoForFileUsesDeepestMatchingRoot() {
        let editorManager = EditorManager()
        let workspace = URL(filePath: "/tmp/codeedit-workspace")
        let root = SourceControlManager(
            workspaceURL: workspace,
            editorManager: editorManager
        )
        let submodule = SourceControlManager(
            workspaceURL: workspace.appending(path: "vendor/lib"),
            editorManager: editorManager,
            isSubmodule: true,
            parentRepoURL: workspace
        )
        let repositories = [root, submodule]

        #expect(SourceControlCoordinator.mostSpecificRepository(
            for: workspace.appending(path: "README.md"),
            in: repositories
        ) === root)
        #expect(SourceControlCoordinator.mostSpecificRepository(
            for: workspace.appending(path: "vendor/lib/Sources/File.swift"),
            in: repositories
        ) === submodule)
        #expect(SourceControlCoordinator.mostSpecificRepository(
            for: workspace.appending(path: "vendor/lib"),
            in: repositories
        ) === submodule)
    }

    @Test
    func repoForFileDoesNotMatchSiblingPrefix() {
        let editorManager = EditorManager()
        let workspace = URL(filePath: "/tmp/codeedit-workspace")
        let manager = SourceControlManager(
            workspaceURL: workspace,
            editorManager: editorManager
        )

        #expect(SourceControlCoordinator.mostSpecificRepository(
            for: URL(filePath: "/tmp/codeedit-workspace-other/README.md"),
            in: [manager]
        ) == nil)
    }
}
