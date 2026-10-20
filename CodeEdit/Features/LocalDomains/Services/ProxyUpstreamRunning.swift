import Foundation

/// Optional dev-server command for reverse-proxy sites. The app only ever stops an upstream it
/// started itself, so a user-managed process on the same port is never touched.
@MainActor
protocol ProxyUpstreamRunning: AnyObject {
    var isRunning: Bool { get }
    /// Recent output from the upstream command, for readiness failures.
    var outputTail: String? { get }
    func start(site: LocalSiteSettings, workspaceURL: URL) async throws
    func stop()
}

/// Runs the proxy start command through the workspace's ``TaskManager`` (so its output is visible and
/// the project's runtime PATH is active), and records the task it created for targeted shutdown.
@MainActor
final class TaskManagerProxyUpstream: ProxyUpstreamRunning {
    private weak var taskManager: TaskManager?
    private var runningTaskID: UUID?

    var isRunning: Bool {
        guard let runningTaskID, let taskManager else {
            return false
        }
        return taskManager.taskStatus(taskID: runningTaskID) == .running
    }

    var outputTail: String? {
        guard let runningTaskID,
              let text = taskManager?.activeTasks[runningTaskID]?.output?.getBufferAsString(),
              !text.isEmpty else {
            return nil
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(20)
        return String(lines.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    func start(site: LocalSiteSettings, workspaceURL: URL) async throws {
        guard let taskManager else {
            return
        }
        let command = site.proxy.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return
        }

        stop()

        let workingDirectory = try Self.workingDirectory(
            for: site.proxy.workingDirectory,
            workspaceURL: workspaceURL
        )
        let task = CETask(
            name: site.domain.isEmpty ? "Local Site Upstream" : "\(site.domain) upstream",
            target: "My Mac",
            workingDirectory: workingDirectory.path(percentEncoded: false),
            command: command
        )
        task.environmentVariables = [
            CETask.EnvironmentVariable(key: "HOST", value: "127.0.0.1"),
            CETask.EnvironmentVariable(key: "PORT", value: String(site.proxy.port))
        ]

        await taskManager.runTask(task: task)
        runningTaskID = task.id
    }

    func stop() {
        guard let runningTaskID, let taskManager else {
            return
        }
        taskManager.activeTasks[runningTaskID]?.terminateProcessTree()
        self.runningTaskID = nil
    }

    /// Resolves the proxy working directory relative to the project and rejects escapes.
    static func workingDirectory(for relativePath: String, workspaceURL: URL) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty
            ? workspaceURL
            : workspaceURL.appending(path: trimmed, directoryHint: .isDirectory)
        let workspace = workspaceURL.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let workspacePath = normalizedPath(workspace)
        let resolvedPath = normalizedPath(resolved)

        guard resolvedPath == workspacePath || resolvedPath.hasPrefix(workspacePath + "/") else {
            throw LocalSiteError.processFailed("The upstream working directory must be inside the project.")
        }
        return resolved
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
