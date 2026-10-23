import Foundation

enum AssistantPathUtilities {
    static func relativePath(for url: URL, root: URL) -> String {
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath

        if filePath == normalizedRoot {
            return url.lastPathComponent
        }
        if filePath.hasPrefix(normalizedRoot + "/") {
            return String(filePath.dropFirst(normalizedRoot.count + 1))
        }
        return url.lastPathComponent
    }

    static func url(forRelativePath relativePath: String, root: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return nil }
        let rootURL = root.standardizedFileURL
        let candidate = rootURL.appending(path: trimmed).standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let candidatePath = candidate.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(prefix) else { return nil }
        return candidate
    }

    static func containsAbsoluteUserPath(_ text: String) -> Bool {
        text.contains(NSHomeDirectory())
    }
}
