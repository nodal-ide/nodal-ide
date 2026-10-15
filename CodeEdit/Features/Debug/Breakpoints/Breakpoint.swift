//
//  Breakpoint.swift
//  CodeEdit
//

import Foundation

/// A user breakpoint in a source file.
struct Breakpoint: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Absolute file path (so breakpoints survive workspace moves).
    var filePath: String
    /// 1-based line number.
    var line: Int
    var enabled: Bool = true
    var condition: String?
    /// Whether the debug adapter verified the breakpoint.
    var verified: Bool = false

    var fileURL: URL { URL(filePath: filePath) }
}
