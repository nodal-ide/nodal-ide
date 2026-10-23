@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct AssistantSelectionContextTests {
    @Test
    func selectionBridgeCapturesExactTextAndLineRange() throws {
        let text = "let a = 1\nlet b = 2\nlet c = 3\n"
        let nsText = text as NSString
        let range = nsText.range(of: "let b = 2")
        let source = AssistantTestSelectionSource(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/Sources/Foo.swift"),
            text: text,
            languageID: "swift",
            selectedRanges: [range],
            zones: [range.location: [AssistantTestData.zone("swift", depth: 0)]]
        )

        let snapshot = try #require(
            AssistantSelectionBridge.snapshot(
                from: source,
                workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
            )
        )

        #expect(snapshot.relativePath == "Sources/Foo.swift")
        #expect(snapshot.languageID == "swift")
        #expect(snapshot.ranges.count == 1)
        #expect(snapshot.ranges.first?.text == "let b = 2")
        #expect(snapshot.ranges.first?.lineRange == 2...2)
        #expect(snapshot.lineRange == 2...2)
        #expect(snapshot.ranges.first?.zones.first?.languageID == "swift")
        #expect(!snapshot.isSecretPath)
    }

    @Test
    func selectionBridgeUsesLiveUnsavedText() throws {
        let text = "let value = 1\nlet changed = 2\n"
        let nsText = text as NSString
        let range = nsText.range(of: "changed")
        let source = AssistantTestSelectionSource(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/Sources/Foo.swift"),
            text: text,
            languageID: "swift",
            selectedRanges: [range]
        )

        let snapshot = try #require(
            AssistantSelectionBridge.snapshot(
                from: source,
                workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
            )
        )

        #expect(snapshot.ranges.first?.text == "changed")
        #expect(snapshot.ranges.first?.lineRange == 2...2)
    }

    @Test
    func selectionBridgeRejectsEmptyAndInvalidRanges() {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let text = "let a = 1\n"
        let empty = AssistantTestSelectionSource(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/Foo.swift"),
            text: text,
            languageID: "swift",
            selectedRanges: []
        )
        #expect(AssistantSelectionBridge.snapshot(from: empty, workspaceRoot: root) == nil)

        let invalid = AssistantTestSelectionSource(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/Foo.swift"),
            text: text,
            languageID: "swift",
            selectedRanges: [NSRange(location: 4, length: 100), NSRange(location: NSNotFound, length: 1)]
        )
        #expect(AssistantSelectionBridge.snapshot(from: invalid, workspaceRoot: root) == nil)
    }

    @Test
    func selectionBridgeCombinesMultipleRangesAndLanguageZones() throws {
        let text = "<?php\necho $value;\n?>\n<div>Hello</div>\n"
        let nsText = text as NSString
        let phpRange = nsText.range(of: "echo $value;")
        let htmlRange = nsText.range(of: "<div>Hello</div>")
        let source = AssistantTestSelectionSource(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/index.php"),
            text: text,
            languageID: "php",
            selectedRanges: [htmlRange, phpRange],
            zones: [
                phpRange.location: [AssistantTestData.zone("php", depth: 0)],
                htmlRange.location: [
                    AssistantTestData.zone("html", depth: 0),
                    AssistantTestData.zone("php", parent: "php", depth: 1)
                ]
            ]
        )

        let snapshot = try #require(
            AssistantSelectionBridge.snapshot(
                from: source,
                workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
            )
        )
        let item = try #require(AssistantContextBuilder.selectionItem(from: snapshot))

        #expect(snapshot.ranges.count == 2)
        #expect(snapshot.lineRange == 2...4)
        #expect(item.zones.map(\.languageID).contains("php"))
        #expect(item.zones.map(\.languageID).contains("html"))
        #expect(item.zones.contains { $0.languageID == "php" && $0.parentLanguageID == "php" })
    }

    @Test
    func selectionBridgeMarksSecretPaths() {
        let text = "password=secret\n"
        let range = (text as NSString).range(of: "password=secret")
        let source = AssistantTestSelectionSource(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/.ssh/config"),
            text: text,
            languageID: "plaintext",
            selectedRanges: [range]
        )

        let snapshot = AssistantSelectionBridge.snapshot(
            from: source,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
        )

        #expect(snapshot?.isSecretPath == true)
        #expect(snapshot?.relativePath == ".ssh/config")
    }

    @Test
    func selectionItemRedactsSecretsAndPreservesExactPreviewText() throws {
        let text = "let apiKey = \"sk-abcdefghijklmnopqrstuvwxyz123456\"\n"
        let snapshot = AssistantSelectionSnapshot(
            fileURL: URL(fileURLWithPath: "/Users/example/Workspace/Sources/Foo.swift"),
            relativePath: "Sources/Foo.swift",
            languageID: "swift",
            ranges: [
                AssistantSelectionRange(
                    lineRange: 1...1,
                    text: text,
                    zones: [AssistantTestData.zone("swift", depth: 0)]
                )
            ],
            isSecretPath: false
        )

        let item = try #require(AssistantContextBuilder.selectionItem(from: snapshot))
        let project = AssistantProjectSnapshot(
            name: "Workspace",
            rootName: "Workspace",
            language: "swift",
            frameworks: ["SwiftUI"]
        )
        let preview = AssistantContextBuilder.preview(items: [item], project: project)

        #expect(item.text.contains("sk-abcdefghijklmnopqrstuvwxyz123456") == false)
        #expect(item.text.contains("[REDACTED]"))
        #expect(item.redactionCount != 0)
        #expect(preview.contextText.contains("[REDACTED]"))
        #expect(preview.contextText.contains("Sources/Foo.swift"))
        #expect(preview.contextText.contains("/Users/example") == false)
        #expect(preview.systemInstructions == AssistantPromptComposer.systemInstructions)
    }

    @Test
    func redactorCoversCommonSecretShapesAndLeavesBenignCodeAlone() {
        let input = """
        let apiKey = "sk-abcdefghijklmnopqrstuvwxyz123456"
        let authorization = "Bearer abcdefghijklmnop"
        let url = "https://user:hunter2@example.com/path"
        let password = "correct-horse"
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA
        -----END RSA PRIVATE KEY-----
        let count = 42
        """
        let result = SecretRedactor.redact(input)

        #expect(result.text.contains("sk-abcdefghijklmnopqrstuvwxyz123456") == false)
        #expect(result.text.contains("Bearer abcdefghijklmnop") == false)
        #expect(result.text.contains("hunter2") == false)
        #expect(result.text.contains("correct-horse") == false)
        #expect(result.text.contains("MIIEowIBAAKCAQEA") == false)
        #expect(result.text.contains("[REDACTED]"))
        #expect(result.text.contains("[REDACTED PRIVATE KEY]"))
        #expect(result.text.contains("let count = 42"))
        #expect(result.count >= 5)

        let benign = SecretRedactor.redact("let count = 42\nprint(\"hello\")\n")
        #expect(benign.text == "let count = 42\nprint(\"hello\")\n")
        #expect(benign.replacements.isEmpty)
    }

    @Test
    func secretPathDetectionCoversSensitiveFiles() {
        #expect(SecretRedactor.isSecretPath(".env"))
        #expect(SecretRedactor.isSecretPath("config/.env.local"))
        #expect(SecretRedactor.isSecretPath(".ssh/config"))
        #expect(SecretRedactor.isSecretPath("keys/id_rsa"))
        #expect(SecretRedactor.isSecretPath("certs/server.pem"))
        #expect(SecretRedactor.isSecretPath("credentials.json"))
        #expect(!SecretRedactor.isSecretPath("Sources/Foo.swift"))
        #expect(!SecretRedactor.isSecretPath("README.md"))
    }
}
