//
//  PerformanceSignposts.swift
//  CodeEdit
//
//  Lightweight `os_signpost` helpers for profiling hot paths in Instruments
//  (use the "Points of Interest" instrument). No-op overhead in normal use.
//

import os
import Foundation

enum PerformanceSignposts {
    static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "CodeEdit",
        category: .pointsOfInterest
    )

    @inline(__always)
    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    @inline(__always)
    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    /// Measures a synchronous block.
    @inline(__always)
    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = begin(name)
        defer { end(name, id: id) }
        return try body()
    }
}
