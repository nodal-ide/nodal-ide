import Foundation

enum AssistantContextBuilder {
    static let selectionID = "C1"
    static let activeFileID = "C2"
    static let openFilesID = "C3"
    static let diagnosticsID = "C4"
    static let tasksID = "C5"
    static let projectID = "C6"

    static func selectionItem(from snapshot: AssistantSelectionSnapshot) -> AssistantContextItem? {
        guard !snapshot.ranges.isEmpty else { return nil }
        let redaction = SecretRedactor.redact(snapshot.text)
        let zones = uniqueZones(snapshot.ranges.flatMap(\.zones))
        var warnings: [String] = []
        if snapshot.isSecretPath {
            warnings.append(contentsOf: SecretRedactor.warnings(forSecretPath: snapshot.relativePath))
        }
        if !redaction.replacements.isEmpty {
            warnings.append("\(redaction.count) possible secret\(redaction.count == 1 ? "" : "s") redacted.")
        }

        let fileName = (snapshot.relativePath as NSString).lastPathComponent
        let title: String
        if let lineRange = snapshot.lineRange {
            let location = lineRange.lowerBound == lineRange.upperBound
                ? "\(fileName):\(lineRange.lowerBound)"
                : "\(fileName):\(lineRange.lowerBound)–\(lineRange.upperBound)"
            title = snapshot.ranges.count > 1
                ? "\(snapshot.ranges.count) selections · \(location)"
                : location
        } else {
            title = fileName
        }

        return AssistantContextItem(
            id: selectionID,
            kind: .selection,
            title: title,
            relativePath: snapshot.relativePath,
            lineRange: snapshot.lineRange,
            languageID: snapshot.languageID,
            zones: zones,
            text: redaction.text,
            isSensitive: snapshot.isSecretPath,
            redactionCount: redaction.count,
            warnings: warnings
        )
    }

    static func activeFileItem(from snapshot: AssistantWorkspaceSnapshot) -> AssistantContextItem? {
        guard let file = snapshot.activeFile else { return nil }
        let redaction = SecretRedactor.redact(file.text)
        var warnings: [String] = []
        if SecretRedactor.isSecretPath(file.relativePath) {
            warnings.append(contentsOf: SecretRedactor.warnings(forSecretPath: file.relativePath))
        }
        if !redaction.replacements.isEmpty {
            warnings.append("\(redaction.count) possible secret\(redaction.count == 1 ? "" : "s") redacted.")
        }

        return AssistantContextItem(
            id: activeFileID,
            kind: .activeFile,
            title: "Active file · \((file.relativePath as NSString).lastPathComponent)",
            relativePath: file.relativePath,
            languageID: file.languageID,
            text: redaction.text,
            isSensitive: SecretRedactor.isSecretPath(file.relativePath),
            redactionCount: redaction.count,
            warnings: warnings
        )
    }

    static func openFilesItem(from snapshot: AssistantWorkspaceSnapshot) -> AssistantContextItem? {
        let safeFiles = snapshot.openFiles.filter { !SecretRedactor.isSecretPath($0.relativePath) }
        guard !safeFiles.isEmpty else { return nil }
        let excludedCount = snapshot.openFiles.count - safeFiles.count
        let ordered = safeFiles.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.relativePath < rhs.relativePath
        }
        let lines = ordered.prefix(40).map { file in
            let active = file.isActive ? " (active)" : ""
            return "- \(file.relativePath) · \(file.languageID)\(active)"
        }
        var warnings: [String] = []
        if excludedCount > 0 {
            warnings.append("\(excludedCount) secret-like open file\(excludedCount == 1 ? "" : "s") excluded.")
        }

        return AssistantContextItem(
            id: openFilesID,
            kind: .openFiles,
            title: "Open files (\(safeFiles.count))",
            text: lines.joined(separator: "\n"),
            warnings: warnings
        )
    }

    static func diagnosticsItem(from snapshot: AssistantWorkspaceSnapshot) -> AssistantContextItem? {
        let activePath = snapshot.activeFile?.relativePath
        let relevant = snapshot.diagnostics
            .filter { $0.severity == "error" || $0.severity == "warning" }
            .filter { !SecretRedactor.isSecretPath($0.relativePath) }
            .sorted { lhs, rhs in
                if (lhs.relativePath == activePath) != (rhs.relativePath == activePath) {
                    return lhs.relativePath == activePath
                }
                if lhs.relativePath != rhs.relativePath {
                    return lhs.relativePath < rhs.relativePath
                }
                return (lhs.line ?? 0) < (rhs.line ?? 0)
            }
        guard !relevant.isEmpty else { return nil }

        let excludedCount = snapshot.diagnostics.count - relevant.count
        let lines = relevant.prefix(50).map { diagnostic -> String in
            var location = diagnostic.relativePath
            if let line = diagnostic.line {
                location += ":\(line)"
                if let column = diagnostic.column {
                    location += ":\(column)"
                }
            }
            var line = "[\(diagnostic.severity)] \(location) \(diagnostic.message)"
            if let ruleID = diagnostic.ruleID {
                line += " (\(ruleID))"
            }
            return line
        }
        var warnings: [String] = []
        if relevant.count > 50 {
            warnings.append("\(relevant.count - 50) additional diagnostics omitted.")
        }
        if excludedCount > 0 {
            warnings.append("\(excludedCount) diagnostics in secret-like files or with lower severity excluded.")
        }

        return AssistantContextItem(
            id: diagnosticsID,
            kind: .diagnostics,
            title: "Diagnostics (\(relevant.count))",
            text: lines.joined(separator: "\n"),
            warnings: warnings
        )
    }

    static func tasksItem(from snapshot: AssistantWorkspaceSnapshot) -> AssistantContextItem? {
        let tasks = snapshot.tasks.filter { !$0.name.isEmpty }.prefix(30)
        guard !tasks.isEmpty else { return nil }

        let lines: [String] = tasks.map { task in
            var line = "- \(task.name)"
            if !task.command.isEmpty {
                line += ": \(task.command)"
            }
            return "\(line) [\(task.status)]"
        }
        let rawText: String = lines.joined(separator: "\n")
        let redaction = SecretRedactor.redact(rawText)
        var warnings: [String] = ["Environment variables are not included."]
        if !redaction.replacements.isEmpty {
            warnings.append("\(redaction.count) possible secret\(redaction.count == 1 ? "" : "s") redacted.")
        }

        return AssistantContextItem(
            id: tasksID,
            kind: .tasks,
            title: "Tasks (\(tasks.count))",
            text: redaction.text,
            redactionCount: redaction.count,
            warnings: warnings
        )
    }

    static func projectItem(from project: AssistantProjectSnapshot) -> AssistantContextItem {
        var lines = [
            "Project: \(project.name)",
            "Folder: \(project.rootName)"
        ]
        if !project.language.isEmpty {
            lines.append("Language: \(project.language)")
        }
        if !project.frameworks.isEmpty {
            lines.append("Frameworks: \(project.frameworks.joined(separator: ", "))")
        }
        let redaction = SecretRedactor.redact(lines.joined(separator: "\n"))

        return AssistantContextItem(
            id: projectID,
            kind: .project,
            title: "Project metadata",
            text: redaction.text,
            redactionCount: redaction.count
        )
    }

    static func packet(
        items: [AssistantContextItem],
        project: AssistantProjectSnapshot?,
        budget: AssistantContextBudget = AssistantContextBudget()
    ) -> AssistantContextPacket {
        var allItems = items
        if let project {
            allItems.append(projectItem(from: project))
        }
        return budget.fit(allItems)
    }

    static func preview(
        items: [AssistantContextItem],
        project: AssistantProjectSnapshot?,
        budget: AssistantContextBudget = AssistantContextBudget()
    ) -> AssistantContextPreview {
        let packet = packet(items: items, project: project, budget: budget)
        return AssistantContextPreview(
            systemInstructions: AssistantPromptComposer.systemInstructions,
            contextText: AssistantPromptComposer.contextText(for: packet),
            items: packet.items,
            estimatedTokens: packet.estimatedTokens,
            warnings: unique(packet.warnings + packet.items.flatMap(\.warnings)),
            omittedTitles: packet.omittedTitles
        )
    }

    private static func uniqueZones(_ zones: [AssistantLanguageZone]) -> [AssistantLanguageZone] {
        var seen = Set<AssistantLanguageZone>()
        return zones.filter { seen.insert($0).inserted }
    }

    private static func unique(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }
}
