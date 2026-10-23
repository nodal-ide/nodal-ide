import Foundation

enum SSEStreamEvent: Equatable, Sendable {
    case event(name: String?, data: String)
}

enum SSEStreamDecoderError: LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case eventTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "The provider sent an invalid UTF-8 event stream."
        case .eventTooLarge:
            return "The provider sent an oversized event stream message."
        }
    }
}

struct SSEStreamDecoder {
    static let maximumLineBytes = 1_024 * 1_024
    static let maximumEventBytes = 2 * 1_024 * 1_024

    private var lineBuffer = Data()
    private var eventName: String?
    private var dataLines: [String] = []
    private var eventBytes = 0

    mutating func append(_ chunk: Data) throws -> [SSEStreamEvent] {
        var events: [SSEStreamEvent] = []
        for byte in chunk {
            events.append(contentsOf: try append(byte))
        }
        return events
    }

    mutating func append(_ byte: UInt8) throws -> [SSEStreamEvent] {
        var events: [SSEStreamEvent] = []
        if byte == 0x0A {
            try appendLine(&events)
        } else {
            lineBuffer.append(byte)
            guard lineBuffer.count <= Self.maximumLineBytes else {
                throw SSEStreamDecoderError.eventTooLarge
            }
        }
        return events
    }

    mutating func finish() throws -> [SSEStreamEvent] {
        var events: [SSEStreamEvent] = []
        if !lineBuffer.isEmpty {
            try appendLine(&events)
        }
        try dispatchEvent(&events)
        return events
    }

    private mutating func appendLine(_ events: inout [SSEStreamEvent]) throws {
        var lineData = lineBuffer
        lineBuffer.removeAll(keepingCapacity: true)
        if lineData.last == 0x0D {
            lineData.removeLast()
        }
        guard let line = String(data: lineData, encoding: .utf8) else {
            throw SSEStreamDecoderError.invalidUTF8
        }
        eventBytes += lineData.count + 1
        guard eventBytes <= Self.maximumEventBytes else {
            throw SSEStreamDecoderError.eventTooLarge
        }

        guard !line.isEmpty else {
            try dispatchEvent(&events)
            return
        }
        guard !line.hasPrefix(":") else {
            return
        }

        let field: String
        let value: String
        if let separator = line.firstIndex(of: ":") {
            field = String(line[..<separator])
            var rawValue = String(line[line.index(after: separator)...])
            if rawValue.hasPrefix(" ") {
                rawValue.removeFirst()
            }
            value = rawValue
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
    }

    private mutating func dispatchEvent(_ events: inout [SSEStreamEvent]) throws {
        defer {
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
            eventBytes = 0
        }
        guard !dataLines.isEmpty else { return }
        events.append(.event(name: eventName, data: dataLines.joined(separator: "\n")))
    }
}
