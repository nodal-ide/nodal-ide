import Foundation
import os

struct ThemeFileIO {
    let userDirectory: URL

    private let fileManager: FileManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "ThemeFileIO"
    )

    init(userDirectory: URL = AppSupportLocations.themesDirectory, fileManager: FileManager = .default) {
        self.userDirectory = userDirectory
        self.fileManager = fileManager
    }

    func save(_ theme: Theme) {
        guard let fileURL = theme.fileURL, isContainedInUserDirectory(fileURL) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(theme.document)
            let object = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            try pretty.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    func duplicate(_ sourceURL: URL) throws -> (url: URL, isImporting: Bool) {
        let sourceIsUserTheme = isContainedInUserDirectory(sourceURL)
        let destination = uniqueDestination(for: sourceURL, sourceIsUserTheme: sourceIsUserTheme)
        try fileManager.copyItem(at: sourceURL, to: destination)
        return (destination, !sourceIsUserTheme)
    }

    func rename(_ theme: Theme, to newDisplayName: String) throws {
        guard let oldURL = theme.fileURL else {
            throw ThemeFileError.missingFile
        }
        guard isContainedInUserDirectory(oldURL) else {
            throw ThemeFileError.notEditable
        }

        var finalName = newDisplayName
        var finalURL = userDirectory.appending(path: finalName).appendingPathExtension("cetheme")
        var iterator = 1
        while finalURL.standardizedFileURL != oldURL.standardizedFileURL,
              fileManager.fileExists(atPath: finalURL.path) {
            finalName = "\(newDisplayName) \(iterator)"
            finalURL = userDirectory.appending(path: finalName).appendingPathExtension("cetheme")
            iterator += 1
        }
        guard finalURL.standardizedFileURL != oldURL.standardizedFileURL else { return }
        try fileManager.moveItem(at: oldURL, to: finalURL)
    }

    func delete(_ theme: Theme) throws {
        guard let url = theme.fileURL, isContainedInUserDirectory(url) else {
            throw ThemeFileError.notEditable
        }
        try fileManager.removeItem(at: url)
    }

    func export(_ theme: Theme, to destinationURL: URL) {
        guard let sourceURL = theme.fileURL else {
            logger.error("Cannot export theme \"\(theme.displayName, privacy: .public)\": no source file")
            return
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            logger.error("Failed to export theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    func exportAllCustomThemes(_ themes: [Theme], to directory: URL) {
        for theme in themes where theme.isEditable {
            guard let sourceURL = theme.fileURL else {
                logger.error(
                    "Cannot export theme \"\(theme.displayName, privacy: .public)\": no source file"
                )
                continue
            }
            let destinationURL = directory.appending(path: "\(theme.displayName).cetheme")
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                logger.error("Failed to export theme: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func isContainedInUserDirectory(_ url: URL) -> Bool {
        let root = userDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(root + "/")
    }

    private func uniqueDestination(for sourceURL: URL, sourceIsUserTheme: Bool) -> URL {
        let fileExtension = sourceURL.pathExtension
        var fileName = sourceURL.deletingPathExtension().lastPathComponent
        var destination = userDirectory
            .appending(path: fileName)
            .appendingPathExtension(fileExtension)
        var iterator = 1

        if !sourceIsUserTheme, fileManager.fileExists(atPath: destination.path) {
            fileName = "\(fileName) \(iterator)"
            destination = userDirectory
                .appending(path: fileName)
                .appendingPathExtension(fileExtension)
        }

        while fileManager.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            let stripped = base.replacingOccurrences(
                of: " \\d+$",
                with: "",
                options: .regularExpression
            )
            fileName = "\(stripped) \\(iterator)"
            destination = userDirectory
                .appending(path: fileName)
                .appendingPathExtension(fileExtension)
            iterator += 1
        }
        return destination
    }
}

enum ThemeFileError: LocalizedError {
    case missingFile
    case notEditable

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The theme has no file on disk."
        case .notEditable:
            return "Only custom themes can be changed. Duplicate this theme first."
        }
    }
}
