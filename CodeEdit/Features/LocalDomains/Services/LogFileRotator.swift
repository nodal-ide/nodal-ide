import Foundation

/// Size-bounded log rotation. The active file is renamed aside (never truncated), so a process holding
/// the file handle keeps writing to the renamed inode until it is told to reopen its logs.
enum LogFileRotator {
    @discardableResult
    static func rotateIfNeeded(_ url: URL, maxBytes: Int, keep: Int = 2) throws -> Bool {
        let fileManager = FileManager.default
        let path = url.path(percentEncoded: false)

        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              size >= maxBytes else {
            return false
        }

        guard keep > 0 else {
            try fileManager.removeItem(at: url)
            return true
        }

        try? fileManager.removeItem(atPath: "\(path).\(keep)")
        for index in stride(from: keep - 1, through: 1, by: -1) {
            let source = "\(path).\(index)"
            guard fileManager.fileExists(atPath: source) else {
                continue
            }
            try? fileManager.moveItem(atPath: source, toPath: "\(path).\(index + 1)")
        }

        try fileManager.moveItem(atPath: path, toPath: "\(path).1")
        return true
    }
}
