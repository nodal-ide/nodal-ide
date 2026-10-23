import CodeEditSourceEditor
import Foundation

@MainActor
protocol AssistantContextProviding: AnyObject {
    func currentSelection() -> AssistantSelectionSnapshot?
    func workspaceSnapshot() -> AssistantWorkspaceSnapshot?
}

@MainActor
final class WorkspaceAssistantContextProvider: AssistantContextProviding {
    private weak var workspace: WorkspaceDocument?

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    func currentSelection() -> AssistantSelectionSnapshot? {
        guard let workspace,
              let instance = workspace.editorManager?.activeEditor.selectedTab,
              let root = workspaceRoot
        else { return nil }
        let source = LiveEditorSelectionSource(
            instance: instance,
            document: instance.file.fileDocument
        )
        return AssistantSelectionBridge.snapshot(from: source, workspaceRoot: root)
    }

    func workspaceSnapshot() -> AssistantWorkspaceSnapshot? {
        guard let workspace, let root = workspaceRoot else { return nil }
        let editorManager = workspace.editorManager
        let activeInstance = editorManager?.activeEditor.selectedTab
        let activePath = activeInstance.map {
            AssistantPathUtilities.relativePath(for: $0.file.url, root: root)
        }
        let activeFile = activeInstance.map { instance -> AssistantFileSnapshot in
            let source = LiveEditorSelectionSource(
                instance: instance,
                document: instance.file.fileDocument
            )
            return AssistantFileSnapshot(
                relativePath: AssistantPathUtilities.relativePath(for: instance.file.url, root: root),
                languageID: source.languageID,
                text: source.text,
                isActive: true
            )
        }
        let openFiles = openFileSnapshots(
            editorManager: editorManager,
            root: root,
            activePath: activePath
        )
        return AssistantWorkspaceSnapshot(
            project: projectSnapshot(workspace: workspace, root: root),
            activeFile: activeFile,
            openFiles: openFiles,
            diagnostics: diagnosticSnapshots(root: root),
            tasks: taskSnapshots(workspace: workspace)
        )
    }

    private var workspaceRoot: URL? {
        workspace?.workspaceFileManager?.folderUrl ?? workspace?.fileURL
    }

    private func openFileSnapshots(
        editorManager: EditorManager?,
        root: URL,
        activePath: String?
    ) -> [AssistantFileSnapshot] {
        guard let editorManager else { return [] }
        var seen = Set<String>()
        var files: [AssistantFileSnapshot] = []

        for editor in editorManager.flattenedEditors {
            var instances = Array(editor.tabs)
            if let temporaryTab = editor.temporaryTab {
                instances.append(temporaryTab)
            }
            for instance in instances {
                let path = AssistantPathUtilities.relativePath(for: instance.file.url, root: root)
                guard seen.insert(path).inserted else { continue }
                let source = LiveEditorSelectionSource(
                    instance: instance,
                    document: instance.file.fileDocument
                )
                files.append(
                    AssistantFileSnapshot(
                        relativePath: path,
                        languageID: source.languageID,
                        text: "",
                        isActive: path == activePath
                    )
                )
            }
        }
        return files
    }

    private func projectSnapshot(workspace: WorkspaceDocument, root: URL) -> AssistantProjectSnapshot {
        let settings = workspace.workspaceSettingsManager?.settings.project
        let rootName = root.lastPathComponent.isEmpty ? "Workspace" : root.lastPathComponent
        let name = settings?.projectName.isEmpty == false ? settings?.projectName ?? rootName : rootName
        return AssistantProjectSnapshot(
            name: name,
            rootName: rootName,
            language: settings?.language ?? "",
            frameworks: settings?.frameworks ?? []
        )
    }

    private func diagnosticSnapshots(root: URL) -> [AssistantDiagnosticSnapshot] {
        DiagnosticsStore.shared.problems(in: root).map { problem in
            AssistantDiagnosticSnapshot(
                relativePath: AssistantPathUtilities.relativePath(for: problem.fileURL, root: root),
                line: problem.line,
                column: problem.column,
                severity: severityLabel(problem.severity),
                message: problem.message,
                ruleID: problem.ruleID,
                languageID: problem.languageContext?.languageID.rawValue
            )
        }
    }

    private func taskSnapshots(workspace: WorkspaceDocument) -> [AssistantTaskSnapshot] {
        (workspace.taskManager?.availableTasks ?? []).map { task in
            AssistantTaskSnapshot(
                name: task.name,
                command: task.command,
                status: statusLabel(workspace.taskManager?.taskStatus(taskID: task.id) ?? .notRunning)
            )
        }
    }

    private func severityLabel(_ severity: EditorDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info:
            return "info"
        case .hint:
            return "hint"
        }
    }

    private func statusLabel(_ status: CETaskStatus) -> String {
        switch status {
        case .notRunning:
            return "not running"
        case .stopped:
            return "stopped"
        case .running:
            return "running"
        case .failed:
            return "failed"
        case .finished:
            return "finished"
        }
    }
}
