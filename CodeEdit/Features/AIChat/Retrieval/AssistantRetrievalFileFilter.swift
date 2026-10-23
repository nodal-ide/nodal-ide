import Foundation

enum AssistantRetrievalFileFilter {
    static let maximumFileSize = 1_048_576

    private static let ignoredDirectoryNames: Set<String> = [
        ".build", ".git", ".hg", ".svn", ".swiftpm", ".venv", ".yarn", ".next",
        "build", "DerivedData", "dist", "node_modules", "out", "Pods", "target",
        "vendor", "venv", "__pycache__"
    ]

    private static let ignoredFileNames: Set<String> = [
        "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Podfile.lock", "Cargo.lock",
        "forge-lock.json"
    ]

    private static let ignoredExtensions: Set<String> = [
        "a", "app", "bin", "bmp", "class", "dylib", "dmg", "doc", "docx", "dylib",
        "eot", "exe", "gif", "gz", "ico", "jar", "jpeg", "jpg", "lock", "min.js",
        "min.css", "mov", "mp3", "mp4", "o", "otf", "pdf", "png", "so", "sqlite",
        "sqlite3", "tar", "tiff", "ttf", "wav", "webm", "webp", "woff", "woff2",
        "xcarchive", "xcodeproj", "xcworkspace", "zip"
    ]

    static func isIgnored(
        relativePath: String,
        isDirectory: Bool,
        excludedGlobs: [String] = []
    ) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return true }

        if components.contains(where: { component in
            component.hasPrefix(".") || ignoredDirectoryNames.contains(component)
        }) {
            return true
        }

        if excludedGlobs.contains(where: { matchesGlob(normalized, pattern: $0) }) {
            return true
        }

        guard let fileName = components.last else { return true }
        if isDirectory {
            return false
        }
        if ignoredFileNames.contains(fileName) {
            return true
        }
        if fileName.hasSuffix(".min.js") || fileName.hasSuffix(".min.css") {
            return true
        }
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        return !fileExtension.isEmpty && ignoredExtensions.contains(fileExtension)
    }

    static func isSecret(relativePath: String) -> Bool {
        SecretRedactor.isSecretPath(relativePath)
    }

    static func isBinary(_ data: Data) -> Bool {
        let prefix = data.prefix(8_192)
        return prefix.contains(0)
    }

    static func decode(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.contains("\u{FFFD}") ? nil : text
    }

    static func languageID(for relativePath: String) -> String {
        let fileExtension = (relativePath as NSString).pathExtension.lowercased()
        return languageIDs[fileExtension] ?? (fileExtension.isEmpty ? "plaintext" : fileExtension)
    }

    private static func matchesGlob(_ path: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let predicate = NSPredicate(format: "SELF LIKE %@", trimmed)
        return predicate.evaluate(with: path)
    }

    private static let languageIDs: [String: String] = [
        "c": "c", "cc": "cpp", "cpp": "cpp", "cs": "csharp", "css": "css",
        "dart": "dart", "go": "go", "h": "c", "hpp": "cpp", "htm": "html",
        "html": "html", "java": "java", "js": "javascript", "json": "json",
        "jsx": "javascriptreact", "kt": "kotlin", "kts": "kotlin", "less": "less",
        "lua": "lua", "md": "markdown", "m": "objective-c", "mm": "objective-cpp",
        "php": "php", "pl": "perl", "py": "python", "rb": "ruby", "rs": "rust",
        "scss": "scss", "sh": "shellscript", "sql": "sql", "svelte": "svelte",
        "swift": "swift", "toml": "toml", "ts": "typescript", "tsx": "typescriptreact",
        "vue": "vue", "xml": "xml", "yaml": "yaml", "yml": "yaml"
    ]
}
