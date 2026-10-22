import Foundation
import GRDB
import OSLog

enum NodalDataMigration {
    private static let logger = Logger(subsystem: "do.upper.nodalide", category: "DataMigration")
    private static let oldDefaultsDomain = "do.upper.codeedit"
    private static let oldAppGroup = "app.codeedit.CodeEdit.shared"
    private static let newAppGroup = "app.nodalide.Nodal.shared"

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nodal", directoryHint: .isDirectory)
    }

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        let completionKey = "NodalDataMigration.v1.completed"
        guard !defaults.bool(forKey: completionKey) else { return }

        let oldRoot = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CodeEdit", directoryHint: .isDirectory)
        var failures: [String] = []

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            for name in ["settings.json", "Themes", "Extensions", "Debug Adapters", "php-debug", "search"] {
                let source = oldRoot.appending(path: name)
                let destination = supportDirectory.appending(path: name)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    logger.notice("Kept existing Nodal data for migration category \(name, privacy: .public)")
                    continue
                }
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                } catch {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }
            do {
                try copyRestorationDatabase(from: oldRoot, to: supportDirectory)
            } catch {
                failures.append("Editor restoration: \(error.localizedDescription)")
            }

            let oldDefaults = UserDefaults(suiteName: oldDefaultsDomain)
            for key in ["recentFiles", "lastFileExtension"] {
                if let value = oldDefaults?.object(forKey: key), defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }

            if let oldGroup = UserDefaults(suiteName: oldAppGroup),
               let newGroup = UserDefaults(suiteName: newAppGroup),
               newGroup.object(forKey: "enableOpenInCE") == nil,
               let enabled = oldGroup.object(forKey: "enableOpenInCE") {
                newGroup.set(enabled, forKey: "enableOpenInCE")
            }
        } catch {
            failures.append("Application Support: \(error.localizedDescription)")
        }

        if failures.isEmpty {
            defaults.set(true, forKey: completionKey)
        } else {
            logger.error("Nodal data migration incomplete; retry will resume. Categories: \(failures.joined(separator: "; "), privacy: .public)")
        }
    }

    private static func copyRestorationDatabase(from sourceRoot: URL, to destinationRoot: URL) throws {
        let fileManager = FileManager.default
        let source = sourceRoot.appending(path: "editor-restoration.db")
        let destination = destinationRoot.appending(path: "editor-restoration.db")
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard !fileManager.fileExists(atPath: destination.path) else {
            logger.notice("Kept existing Nodal editor restoration database")
            return
        }

        let staging = destinationRoot.appending(path: "editor-restoration.\(UUID().uuidString).migration")
        defer { try? fileManager.removeItem(at: staging) }
        let sourceQueue = try DatabaseQueue(path: source.path)
        let stagingQueue = try DatabaseQueue(path: staging.path)
        try sourceQueue.backup(to: stagingQueue)
        try stagingQueue.read { db in
            let result = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard result == "ok" else {
                throw DatabaseError(message: "SQLite integrity check failed: \(result ?? "no result")")
            }
        }
        try stagingQueue.close()
        try sourceQueue.close()
        try fileManager.moveItem(at: staging, to: destination)
    }
}
