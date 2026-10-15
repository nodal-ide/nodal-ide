//
//  DAPTypes.swift
//  CodeEdit
//
//  Typed DAP request arguments and response/event bodies used by the session.
//

import Foundation

// MARK: - Request arguments

struct DAPInitializeArguments: Encodable {
    var clientID: String = "CodeEdit"
    var adapterID: String
    var linesStartAt1: Bool = true
    var columnsStartAt1: Bool = true
    var pathFormat: String = "path"
}

struct DAPThreadArguments: Encodable {
    let threadId: Int
}

struct DAPStackTraceArguments: Encodable {
    let threadId: Int
    var startFrame: Int?
    var levels: Int?
}

struct DAPScopesArguments: Encodable {
    let frameId: Int
}

struct DAPVariablesArguments: Encodable {
    let variablesReference: Int
    var start: Int?
    var count: Int?
}

struct DAPEvaluateArguments: Encodable {
    let expression: String
    var frameId: Int?
    var context: String?
}

struct DAPSetBreakpointsSource: Encodable {
    var name: String?
    var path: String
}

struct DAPSourceBreakpoint: Encodable {
    var line: Int
    var column: Int?
    var condition: String?
}

struct DAPSetBreakpointsArguments: Encodable {
    let source: DAPSetBreakpointsSource
    let breakpoints: [DAPSourceBreakpoint]
}

// MARK: - Response bodies

struct DAPThread: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct DAPThreadsResponse: Decodable {
    let threads: [DAPThread]
}

struct DAPSource: Decodable, Hashable {
    var name: String?
    var path: String?
}

struct DAPStackFrame: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    var source: DAPSource?
    var line: Int
    var column: Int
}

struct DAPStackTraceResponse: Decodable {
    let stackFrames: [DAPStackFrame]
    var totalFrames: Int?
}

struct DAPScope: Decodable, Identifiable, Hashable {
    let name: String
    let variablesReference: Int
    let expensive: Bool
    var id: Int { variablesReference }
}

struct DAPScopesResponse: Decodable {
    let scopes: [DAPScope]
}

struct DAPVariable: Decodable, Hashable {
    let name: String
    let value: String
    var type: String?
    let variablesReference: Int
}

struct DAPVariablesResponse: Decodable {
    let variables: [DAPVariable]
}

struct DAPEvaluateResponse: Decodable {
    let result: String
    var type: String?
    var variablesReference: Int?
}

struct DAPBreakpoint: Decodable, Hashable {
    let id: Int?
    let verified: Bool
    let line: Int?
    let message: String?
}

struct DAPSetBreakpointsResponse: Decodable {
    let breakpoints: [DAPBreakpoint]
}

// MARK: - Event bodies

struct DAPStoppedEventBody: Decodable {
    let reason: String
    var threadId: Int?
    var allThreadsStopped: Bool?
}

struct DAPContinuedEventBody: Decodable {
    var threadId: Int?
}

struct DAPOutputEventBody: Decodable {
    var category: String?
    let output: String
}

struct DAPExitedEventBody: Decodable {
    let exitCode: Int
}
