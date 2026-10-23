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

    static func containsAbsoluteUserPath(_ text: String) -> Bool {
        text.contains(NSHomeDirectory())
    }
}
