@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct AssistantContextBuilderTests {
    @Test
    func contextBuilderUsesRelativePathsAndFiltersSensitiveDiagnostics() {
        let snapshot = AssistantTestData.workspaceSnapshot(rootName: "Workspace")
        let diagnostics = AssistantContextBuilder.diagnosticsItem(from: snapshot)
        let openFiles = AssistantContextBuilder.openFilesItem(from: snapshot)
        let preview = AssistantContextBuilder.preview(
            items: [diagnostics, openFiles].compactMap { $0 },
            project: snapshot.project
        )

        #expect(diagnostics?.text.hasPrefix("[error] Sources/Active.swift:6") == true)
        #expect(diagnostics?.text.contains("Sources/Active.swift:4") == false)
        #expect(diagnostics?.text.contains("Sources/Other.swift:2") == true)
        #expect(diagnostics?.text.contains("hint") == false)
        #expect(diagnostics?.text.contains("certs/server.pem") == false)
        #expect(openFiles?.text.contains("Sources/Active.swift") == true)
        #expect(openFiles?.text.contains("Sources/Other.swift") == true)
        #expect(openFiles?.text.contains("secrets/token.txt") == false)
        #expect(preview.contextText.contains("/Users/example") == false)
        #expect(preview.contextText.contains(NSHomeDirectory()) == false)
    }

    @Test
    func taskContextRedactsCommandsAndNeverIncludesEnvironment() throws {
        let snapshot = AssistantWorkspaceSnapshot(
            project: AssistantProjectSnapshot(name: "App", rootName: "App", language: "swift", frameworks: []),
            activeFile: nil,
            openFiles: [],
            diagnostics: [],
            tasks: [
                AssistantTaskSnapshot(
                    name: "Build",
                    command: "API_TOKEN=sk-abcdefghijklmnopqrstuvwxyz123456 swift build",
                    status: "running"
                )
            ]
        )

        let item = try #require(AssistantContextBuilder.tasksItem(from: snapshot))

        #expect(item.text.contains("Build"))
        #expect(item.text.contains("sk-abcdefghijklmnopqrstuvwxyz123456") == false)
        #expect(item.warnings.contains("Environment variables are not included."))
    }

    @Test
    func budgetTruncatesOversizedSelectionAndOmitsWhenTooSmall() {
        let item = AssistantContextItem(
            id: "C1",
            kind: .selection,
            title: "Huge.swift",
            text: String(repeating: "let value = 1\n", count: 500)
        )
        var budget = AssistantContextBudget()
        budget.maximumContextTokens = 120
        budget.selectionTokens = 120

        let packet = budget.fit([item])

        #expect(packet.items.count == 1)
        #expect(packet.items.first?.isTruncated == true)
        #expect(packet.estimatedTokens <= 120)
        #expect(packet.warnings.isEmpty == false)
        #expect(packet.omittedTitles.isEmpty)

        budget.maximumContextTokens = 40
        budget.selectionTokens = 40
        let omitted = budget.fit([item])
        #expect(omitted.items.isEmpty)
        #expect(omitted.omittedTitles == ["Huge.swift"])
    }

    @Test
    func projectMetadataNeverLeaksAbsolutePaths() {
        let project = AssistantProjectSnapshot(
            name: "Nodal",
            rootName: "Nodal",
            language: "php",
            frameworks: ["laravel/framework"]
        )
        let item = AssistantContextBuilder.projectItem(from: project)
        let preview = AssistantContextBuilder.preview(items: [], project: project)

        #expect(item.text.contains("Nodal"))
        #expect(item.text.contains("laravel/framework"))
        #expect(preview.contextText.contains(NSHomeDirectory()) == false)
        #expect(preview.items.contains { $0.kind == .project })
    }
}
