//
//  TestResult.swift
//  CodeEdit
//
//  A single test outcome (from TAP or JUnit output).
//

import Foundation

struct TestResult: Identifiable, Hashable {
    enum Status: Hashable {
        case passed
        case failed
        case skipped
        case error
    }

    let id = UUID()
    let suite: String
    let name: String
    let status: Status
    let duration: Double?
    let message: String?
    let fileURL: URL?
    let line: Int?
}
