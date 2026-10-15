//
//  RuntimeJobCenter.swift
//  CodeEdit
//
//  Tracks runtime install/uninstall jobs and surfaces them (activity notifications).
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class RuntimeJobCenter: ObservableObject {
    @Published private(set) var jobs: [RuntimeJob] = []

    /// In-flight job tasks, keyed by job id (used for cancellation).
    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Runs a runtime job, reporting progress to the activity area and the jobs list.
    func run(
        kind: RuntimeKind,
        version: String,
        operation: RuntimeJob.Operation,
        action: @escaping (@escaping (RuntimeInstallProgress) -> Void) async throws -> Void
    ) async {
        let id = UUID()
        jobs.append(RuntimeJob(id: id, kind: kind, version: version, operation: operation))

        let notification = NotificationManager.shared.post(
            iconSymbol: kind.systemImage,
            title: "\(operation.title)ing \(kind.title) \(version)",
            description: "Starting…",
            actionButtonTitle: "Stop",
            action: { [weak self] in self?.cancel(id: id) },
            isSticky: true
        )

        let task = Task { [weak self] in
            guard let self else { return }
            await self.execute(
                id: id,
                notification: notification,
                action: action
            )
        }
        tasks[id] = task
        await task.value
        tasks[id] = nil
    }

    /// Cancels a running job (terminating the underlying process/download).
    func cancel(id: UUID) {
        tasks[id]?.cancel()
    }

    private func execute(
        id: UUID,
        notification: CENotification,
        action: @escaping (@escaping (RuntimeInstallProgress) -> Void) async throws -> Void
    ) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let kind = job.kind
        let version = job.version
        let operation = job.operation
        do {
            try await action { [weak self] progress in
                self?.apply(id: id, notification: notification, progress: progress)
            }
            update(id: id, status: .done)
            NotificationManager.shared.dismissNotification(notification)
            NotificationManager.shared.post(
                iconSymbol: kind.systemImage,
                title: "\(operation.titlePast) \(kind.title) \(version)",
                description: "Completed successfully.",
                actionButtonTitle: "Dismiss",
                action: {},
                isSticky: false
            )
        } catch is CancellationError {
            update(id: id, status: .cancelled)
            NotificationManager.shared.dismissNotification(notification)
            NotificationManager.shared.post(
                iconSymbol: "stop.circle.fill",
                iconColor: Color(nsColor: .systemOrange),
                title: "Cancelled \(operation.title.lowercased()) \(kind.title) \(version)",
                description: "The operation was stopped.",
                actionButtonTitle: "Dismiss",
                action: {},
                isSticky: false
            )
        } catch {
            update(id: id, status: .failed(error.localizedDescription))
            NotificationManager.shared.dismissNotification(notification)
            NotificationManager.shared.post(
                iconSymbol: "exclamationmark.triangle.fill",
                iconColor: Color(nsColor: .systemRed),
                title: "Failed to \(operation.title.lowercased()) \(kind.title) \(version)",
                description: error.localizedDescription,
                actionButtonTitle: "Dismiss",
                action: {},
                isSticky: true
            )
        }
    }

    private func apply(id: UUID, notification: CENotification, progress: RuntimeInstallProgress) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].phase = progress.phase
        jobs[index].fraction = progress.fraction
        NotificationManager.shared.updateNotification(
            notification,
            description: Self.describe(progress)
        )
    }

    private func update(id: UUID, status: RuntimeJob.Status) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
    }

    private static func describe(_ progress: RuntimeInstallProgress) -> String {
        if let message = progress.message, !message.isEmpty {
            return message
        }
        if let fraction = progress.fraction {
            return "\(progress.phase.title)… \(Int(fraction * 100))%"
        }
        return "\(progress.phase.title)…"
    }
}
