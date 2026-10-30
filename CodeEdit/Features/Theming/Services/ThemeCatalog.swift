import Foundation
import CodeEditLang
import os

struct ThemeSnapshot {
    let themes: [Theme]
    private let indexByID: [String: Int]

    init(themes: [Theme]) {
        self.themes = themes
        var index: [String: Int] = [:]
        index.reserveCapacity(themes.count)
        for (offset, theme) in themes.enumerated() where index[theme.id] == nil {
            index[theme.id] = offset
        }
        self.indexByID = index
    }

    func theme(id: String?) -> Theme? {
        guard let id, let offset = indexByID[id] else { return nil }
        return themes[offset]
    }

    func theme(named name: String?) -> Theme? {
        guard let name else { return nil }
        let matches = themes.filter { $0.name == name || $0.displayName == name }
        return matches.first { $0.source == .user } ?? matches.first
    }

    var darkThemes: [Theme] {
        themes.filter { $0.appearance == .dark }
    }

    var lightThemes: [Theme] {
        themes.filter { $0.appearance == .light }
    }
}

final class ThemeCatalog {
    private let fileManager: FileManager
    private let extensionStore: LanguageExtensionStore
    private let bundledDirectory: URL?
    let userDirectory: URL

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "ThemeCatalog"
    )

    init(
        bundledDirectory: URL? = AppSupportLocations.bundledThemesDirectory,
        userDirectory: URL = AppSupportLocations.themesDirectory,
        extensionStore: LanguageExtensionStore = .shared,
        fileManager: FileManager = .default
    ) {
        self.bundledDirectory = bundledDirectory
        self.userDirectory = userDirectory
        self.extensionStore = extensionStore
        self.fileManager = fileManager
    }

    func load(preferences: SettingsData) -> ThemeSnapshot {
        ensureUserDirectory()

        var themes: [Theme] = []
        if let bundledDirectory {
            themes.append(contentsOf: loadPack(at: bundledDirectory, source: .bundled, strict: true))
        }
        themes.append(contentsOf: loadUserThemes())
        themes.append(contentsOf: loadExtensionThemes(preferences: preferences))

        let overrides = preferences.theme.overrides
        for offset in themes.indices {
            applyOverrides(
                overrides[themes[offset].id] ?? overrides[themes[offset].name],
                to: &themes[offset]
            )
        }

        return ThemeSnapshot(themes: themes)
    }

    private func ensureUserDirectory() {
        var isDirectory: ObjCBool = false
        guard !fileManager.fileExists(atPath: userDirectory.path, isDirectory: &isDirectory) else {
            return
        }
        do {
            try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create themes directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadUserThemes() -> [Theme] {
        let urls = themeFileURLs(in: userDirectory)
        var themes: [Theme] = []
        for url in urls {
            guard let document = decodeDocument(at: url, strict: false) else { continue }
            themes.append(
                Theme(id: "user:\(document.name)", source: .user, fileURL: url, document: document)
            )
        }
        return themes.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func loadExtensionThemes(preferences: SettingsData) -> [Theme] {
        let disabled = Set(preferences.extensions.disabledExtensions)
        var themes: [Theme] = []
        for pack in extensionStore.globalExtensions() where !disabled.contains(pack.id) {
            let source = ThemeSource.extensionPack(id: pack.id, name: pack.name)
            themes.append(contentsOf: loadPack(at: pack.root, source: source, strict: true))
        }
        return themes
    }

    private func loadPack(at root: URL, source: ThemeSource, strict: Bool) -> [Theme] {
        guard let manifest = decode(
            LanguageExtensionManifest.self,
            at: root.appending(path: "extension.json"),
            descriptor: "manifest"
        ) else {
            return []
        }
        guard let contributions = manifest.contributes?.themes, !contributions.isEmpty else {
            return []
        }

        var themes: [Theme] = []
        var identifiers = Set<String>()
        for contribution in contributions {
            guard !contribution.id.isEmpty, identifiers.insert(contribution.id).inserted else {
                logger.error("Skipping duplicate theme contribution '\(contribution.id, privacy: .public)'.")
                continue
            }
            guard let url = LanguageExtensionPaths.resolve(contribution.path, in: root),
                  LanguageExtensionPaths.isContained(url, in: root) else {
                logger.error(
                    "Theme path escapes the pack root: \(contribution.path, privacy: .public)"
                )
                continue
            }
            guard let document = decodeDocument(at: url, strict: strict) else { continue }
            themes.append(
                Theme(
                    id: identifier(for: source, contributionID: contribution.id, document: document),
                    source: source,
                    fileURL: url,
                    document: document
                )
            )
        }
        return themes
    }

    private func identifier(
        for source: ThemeSource,
        contributionID: String,
        document: ThemeDocument
    ) -> String {
        switch source {
        case .bundled:
            return "bundled:\(contributionID)"
        case .user:
            return "user:\(document.name)"
        case let .extensionPack(id, _):
            return "ext:\(id)/\(contributionID)"
        }
    }

    private func themeFileURLs(in directory: URL) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            if fileManager.fileExists(atPath: directory.path) {
                logger.error("Failed to list themes in \(directory.path, privacy: .public)")
            }
            return []
        }
        return entries
            .filter { $0.pathExtension.caseInsensitiveCompare("cetheme") == .orderedSame }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func decodeDocument(at url: URL, strict: Bool) -> ThemeDocument? {
        guard let document = decode(ThemeDocument.self, at: url, descriptor: "theme") else {
            return nil
        }
        let validation = ThemeDocumentValidator.validate(document: document)
        for issue in validation.issues {
            logger.warning(
                "\(url.lastPathComponent, privacy: .public): \(issue.description, privacy: .public)"
            )
        }
        if strict, !validation.isValid {
            return nil
        }
        return document
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL, descriptor: String) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            if fileManager.fileExists(atPath: url.path) {
                logger.error("Failed to read \(descriptor, privacy: .public) at \(url.path, privacy: .public)")
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let reason = LanguageExtensionValidator.describe(error)
            let message = "Failed to decode \(descriptor) at \(url.path): \(reason)"
            logger.error("\(message, privacy: .public)")
            return nil
        }
    }

    private func applyOverrides(
        _ overrides: SettingsData.ThemeOverrides?,
        to theme: inout Theme
    ) {
        guard let overrides else { return }
        if let editor = overrides["editor"] {
            for (key, attributes) in editor {
                theme.editor[key] = attributes
            }
        }
        if let terminal = overrides["terminal"] {
            for (key, attributes) in terminal {
                theme.terminal[key] = attributes
            }
        }
    }
}
