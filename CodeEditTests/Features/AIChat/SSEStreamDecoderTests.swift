@testable import CodeEdit
import Foundation
import Testing

@Suite
struct SSEStreamDecoderTests {
    @Test
    func parsesDataEventAndDone() throws {
        var decoder = SSEStreamDecoder()
        let events = try decoder.append(Data("data: hello\n\ndata: [DONE]\n\n".utf8))

        #expect(events == [
            .event(name: nil, data: "hello"),
            .event(name: nil, data: "[DONE]")
        ])
    }

    @Test
    func parsesEventNameAndMultilineData() throws {
        var decoder = SSEStreamDecoder()
        let events = try decoder.append(Data("event: message\ndata: first\ndata: second\n\n".utf8))

        #expect(events == [.event(name: "message", data: "first\nsecond")])
    }

    @Test
    func ignoresCommentsKeepalivesAndCRLF() throws {
        var decoder = SSEStreamDecoder()
        let events = try decoder.append(Data(": keepalive\r\ndata: value\r\n\r\n".utf8))

        #expect(events == [.event(name: nil, data: "value")])
    }

    @Test
    func handlesUTF8SplitAcrossChunks() throws {
        let data = Data("data: ¡Hola!\n\n".utf8)
        let split = data.index(data.startIndex, offsetBy: 7)
        var decoder = SSEStreamDecoder()

        #expect(try decoder.append(data[..<split]).isEmpty)
        #expect(try decoder.append(data[split...]) == [.event(name: nil, data: "¡Hola!")])
    }

    @Test
    func finishesEventWithoutTrailingBlankLine() throws {
        var decoder = SSEStreamDecoder()
        #expect(try decoder.append(Data("data: tail".utf8)).isEmpty)
        #expect(try decoder.finish() == [.event(name: nil, data: "tail")])
    }

    @Test
    func rejectsInvalidUTF8() {
        var decoder = SSEStreamDecoder()
        let data = Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0x20, 0xFF, 0x0A])

        do {
            _ = try decoder.append(data)
            Issue.record("Expected invalid UTF-8 to be rejected.")
        } catch let error as SSEStreamDecoderError {
            #expect(error == .invalidUTF8)
        } catch {
            Issue.record("Unexpected error \(error).")
        }
    }
}
