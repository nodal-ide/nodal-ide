@testable import CodeEdit
import Foundation
import Testing

@MainActor
struct AssistantTestSelectionSource: AssistantSelectionSource {
    let fileURL: URL?
    let text: String
    let languageID: String
    let selectedRanges: [NSRange]
    var zones: [Int: [AssistantLanguageZone]] = [:]

    func languageZones(at location: Int) -> [AssistantLanguageZone] {
        zones[location] ?? [AssistantTestData.zone(languageID, depth: 0)]
    }
}

@MainActor
final class AssistantTestContextProvider: AssistantContextProviding {
    var selection: AssistantSelectionSnapshot?
    var snapshot: AssistantWorkspaceSnapshot?

    func currentSelection() -> AssistantSelectionSnapshot? {
        selection
    }

    func workspaceSnapshot() -> AssistantWorkspaceSnapshot? {
        snapshot
    }
}

final class AssistantTestRecordingTransport: AssistantTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [AssistantRequest] = []

    var requests: [AssistantRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantTransportEvent, Error> {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            continuation.yield(.delta("ok"))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

@MainActor
enum AssistantTestData {
    static func zone(
        _ languageID: String,
        parent: String? = nil,
        depth: Int
    ) -> AssistantLanguageZone {
        AssistantLanguageZone(
            languageID: languageID,
            parentLanguageID: parent,
            sourceKey: nil,
            depth: depth
        )
    }

    static func selectionSnapshot(
        relativePath: String = "Sources/Active.swift",
        secret: Bool = false
    ) -> AssistantSelectionSnapshot {
        AssistantSelectionSnapshot(
            fileURL: URL(fileURLWithPath: "/tmp/workspace/\(relativePath)"),
            relativePath: relativePath,
            languageID: "swift",
            ranges: [
                AssistantSelectionRange(
                    lineRange: 2...2,
                    text: "let value = 2",
                    zones: [zone("swift", depth: 0)]
                )
            ],
            isSecretPath: secret
        )
    }

    static func workspaceSnapshot(rootName: String) -> AssistantWorkspaceSnapshot {
        AssistantWorkspaceSnapshot(
            project: AssistantProjectSnapshot(
                name: rootName,
                rootName: rootName,
                language: "swift",
                frameworks: ["SwiftUI"]
            ),
            activeFile: assistantTestActiveFile,
            openFiles: assistantTestOpenFiles,
            diagnostics: assistantTestDiagnostics,
            tasks: [AssistantTaskSnapshot(name: "Build", command: "swift build", status: "not running")]
        )
    }

    private static let assistantTestActiveFile = AssistantFileSnapshot(
        relativePath: "Sources/Active.swift",
        languageID: "swift",
        text: "let value = 2\n",
        isActive: true
    )

    private static let assistantTestOpenFiles = [
        AssistantFileSnapshot(
            relativePath: "Sources/Active.swift",
            languageID: "swift",
            text: "",
            isActive: true
        ),
        AssistantFileSnapshot(
            relativePath: "Sources/Other.swift",
            languageID: "swift",
            text: "",
            isActive: false
        ),
        AssistantFileSnapshot(
            relativePath: "secrets/token.txt",
            languageID: "plaintext",
            text: "",
            isActive: false
        )
    ]

    private static let assistantTestDiagnostics = [
        AssistantDiagnosticSnapshot(
            relativePath: "Sources/Active.swift",
            line: 4,
            column: 3,
            severity: "hint",
            message: "hint message",
            ruleID: "swift.hint",
            languageID: "swift"
        ),
        AssistantDiagnosticSnapshot(
            relativePath: "Sources/Other.swift",
            line: 2,
            column: 1,
            severity: "warning",
            message: "warning message",
            ruleID: "swift.warning",
            languageID: "swift"
        ),
        AssistantDiagnosticSnapshot(
            relativePath: "certs/server.pem",
            line: 1,
            column: 1,
            severity: "error",
            message: "secret diagnostic",
            ruleID: nil,
            languageID: nil
        ),
        AssistantDiagnosticSnapshot(
            relativePath: "Sources/Active.swift",
            line: 6,
            column: 1,
            severity: "error",
            message: "active error",
            ruleID: "swift.error",
            languageID: "swift"
        )
    ]

    static func waitForIdle(
        _ session: AssistantSession,
        timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while session.isStreaming && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!session.isStreaming)
    }
}
