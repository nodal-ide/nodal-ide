//
//  RuntimeJob.swift
//  CodeEdit
//

import Foundation

/// A running (or finished) runtime install/uninstall job.
struct RuntimeJob: Identifiable, Equatable {
    enum Operation: String {
        case install
        case uninstall

        var title: String {
            switch self {
            case .install: return "Install"
            case .uninstall: return "Uninstall"
            }
        }

        var titlePast: String {
            switch self {
            case .install: return "Installed"
            case .uninstall: return "Removed"
            }
        }
    }

    enum Status: Equatable {
        case running
        case done
        case cancelled
        case failed(String)
    }

    let id: UUID
    let kind: RuntimeKind
    let version: String
    let operation: Operation
    var phase: RuntimeInstallProgress.Phase = .resolving
    var fraction: Double?
    var status: Status = .running
}
