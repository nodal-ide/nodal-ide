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
            actionButtonTitle: "Dismiss",
            action: {},
            isSticky: true
        )

        do {
            try await action { [weak self] progress in
                self?.apply(id: id, progress: progress)
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

    private func apply(id: UUID, progress: RuntimeInstallProgress) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].phase = progress.phase
        jobs[index].fraction = progress.fraction
    }

    private func update(id: UUID, status: RuntimeJob.Status) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
    }
}
