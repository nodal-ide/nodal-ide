//
//  ConflictModel.swift
//  CodeEdit
//
//  Models for git merge conflicts.
//

import Foundation

/// A single conflict region in a file.
struct ConflictBlock: Identifiable, Hashable {
    let id = UUID()
    /// The whole conflict region (`<<<<<<<` … `>>>>>>>`), including trailing line endings.
    let range: NSRange
    /// The "ours" (current) side.
    let ours: String
    /// The "theirs" (incoming) side.
    let theirs: String
    /// The common base, if the conflict uses diff3 markers (`|||||||`).
    let base: String?
    /// The label after `<<<<<<<` (e.g. `HEAD`).
    let oursLabel: String
    /// The label after `>>>>>>>` (e.g. the branch).
    let theirsLabel: String
}

/// A file parsed for conflicts.
struct ConflictFile {
    let content: String
    let conflicts: [ConflictBlock]

    var hasConflicts: Bool { !conflicts.isEmpty }
}

/// How to resolve a conflict.
enum ConflictResolution {
    case ours
    case theirs
    /// Keep both sides (ours first when `oursFirst`).
    case both(oursFirst: Bool)
    /// Keep the base (diff3 only).
    case base

    func text(for conflict: ConflictBlock) -> String {
        switch self {
        case .ours: return conflict.ours
        case .theirs: return conflict.theirs
        case .both(let oursFirst):
            return oursFirst ? conflict.ours + conflict.theirs : conflict.theirs + conflict.ours
        case .base: return conflict.base ?? ""
        }
    }
}
