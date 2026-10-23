@testable import CodeEdit
import Foundation
import Testing
struct ConversationFixture {
    let workspaceURL: URL
    let storageRoot: URL
    let store: AssistantConversationStore

    init(retention: AssistantConversationRetention = AssistantConversationRetention()) throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "AssistantConversationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspaceURL = base.appending(path: "Workspace", directoryHint: .isDirectory)
        storageRoot = base.appending(path: "Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        store = AssistantConversationStore(
            workspaceURL: workspaceURL,
            storageRoot: storageRoot,
            retention: retention
        )
    }

    func writeArchive(_ text: String) throws {
        try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
        try text.write(to: store.archiveURL, atomically: true, encoding: .utf8)
    }

    func writeArchiveJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
        try data.write(to: store.archiveURL, options: .atomic)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
    }
}
