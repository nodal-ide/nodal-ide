//
//  DAPMessage.swift
//  CodeEdit
//
//  Debug Adapter Protocol message envelopes.
//

import Foundation

/// A request sent from the client to the debug adapter.
struct DAPRequest: Encodable {
    let seq: Int
    let type = "request"
    let command: String
    let arguments: JSONValue?
}

/// A response to a request.
struct DAPResponse: Decodable {
    let seq: Int
    let requestSeq: Int
    let success: Bool
    let command: String
    let message: String?
    let body: JSONValue?

    enum CodingKeys: String, CodingKey {
        case seq
        case requestSeq = "request_seq"
        case success
        case command
        case message
        case body
    }
}

/// An event sent from the debug adapter.
struct DAPEvent: Decodable {
    let seq: Int
    let event: String
    let body: JSONValue?
}

/// Used to inspect a message's `type` before decoding it fully.
struct DAPTypePeek: Decodable {
    let type: String
}

enum DAPError: LocalizedError {
    case notRunning
    case terminated
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notRunning: return "The debug adapter is not running."
        case .terminated: return "The debug adapter terminated."
        case .writeFailed: return "Failed to write to the debug adapter."
        }
    }
}
