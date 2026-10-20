import Foundation

/// Reads a bounded tail of a log file without loading the whole file into memory. Seeks within
/// `maxBytes` of the end, drops a possibly-partial leading line, and returns at most `maxLines`.
enum LogFileTail {
    static func lines(at url: URL, maxLines: Int = 200, maxBytes: Int = 64 * 1024) throws -> [String] {
        guard maxLines > 0, maxBytes > 0 else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()

        var payload = data
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            payload = data[data.index(after: newline)...]
        }

        guard let text = String(data: payload, encoding: .utf8) else {
            return []
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return Array(lines.suffix(maxLines))
    }
}
