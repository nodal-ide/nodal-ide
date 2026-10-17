//
//  ProjectScanStatus.swift
//  CodeEdit
//
//  Surfaces PHP project-scan progress in the Activity Viewer (like search indexing).
//

import Foundation

/// Tracks per-workspace project-scan progress and reports it through the Activity Viewer's task
/// notifications. Fast (fully-cached) scans don't flash — the task is only shown if the scan takes
/// longer than a short grace period — and progress updates are throttled.
@MainActor
final class ProjectScanStatus {
    static let shared = ProjectScanStatus()

    private struct State {
        var id: String?
        var startTask: Task<Void, Never>?
        var completed = 0
        var total = 0
        var lastFraction = -1.0
    }

    private var states: [String: State] = [:]
    private let title = "Scanning | Processing PHP files"
    private let graceMilliseconds = 400

    private init() {}

    /// Records progress for a workspace. `completed >= total` finishes the task.
    func update(root: URL, completed: Int, total: Int) {
        guard total > 0 else { return }
        let key = root.path(percentEncoded: false)
        var state = states[key] ?? State()
        state.completed = completed
        state.total = total

        if completed >= total {
            state.startTask?.cancel()
            if let id = state.id {
                finish(root: root, id: id, total: total)
            }
            states[key] = nil
            return
        }

        let fraction = Double(completed) / Double(total)
        if state.id == nil {
            if state.startTask == nil {
                state.startTask = Task { [weak self, key] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    self?.begin(root: root, key: key)
                }
            }
        } else if fraction - state.lastFraction >= 0.005 {
            state.lastFraction = fraction
            let id = state.id ?? ""
            post(root: root, action: .update, model: TaskNotificationModel(
                id: id,
                title: title,
                message: "\(completed) / \(total) files",
                percentage: fraction,
                isLoading: true
            ))
        }
        states[key] = state
    }

    // MARK: - Private

    private func begin(root: URL, key: String) {
        guard var state = states[key], state.id == nil, state.completed < state.total else { return }
        let id = UUID().uuidString
        state.id = id
        state.startTask = nil
        state.lastFraction = Double(state.completed) / Double(max(1, state.total))
        states[key] = state
        post(root: root, action: .createWithPriority, model: TaskNotificationModel(
            id: id,
            title: title,
            message: "\(state.completed) / \(state.total) files",
            percentage: state.lastFraction,
            isLoading: true
        ))
    }

    private func finish(root: URL, id: String, total: Int) {
        post(root: root, action: .update, model: TaskNotificationModel(
            id: id,
            title: "Finished scanning",
            message: "Scanned \(total) file\(total == 1 ? "" : "s")",
            percentage: 1,
            isLoading: false
        ))
        NotificationCenter.default.post(
            name: .taskNotification,
            object: nil,
            userInfo: ["id": id, "action": "deleteWithDelay", "delay": 4.0, "workspace": root]
        )
    }

    private func post(root: URL, action: TaskNotificationHandler.Action, model: TaskNotificationModel) {
        TaskNotificationHandler.postTask(toWorkspace: root, action: action, model: model)
    }
}
