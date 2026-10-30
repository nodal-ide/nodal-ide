import Foundation
import Testing
import CodeEditLang
@testable import CodeEdit

@Suite
struct ThemeCatalogTests {
    @Test
    func discoversBundledUserAndExtensionThemes() throws {
        let fixture = try ThemeFixture()
        let snapshot = fixture.catalog.load(preferences: SettingsData())

        #expect(snapshot.themes.map(\.id) == [
            "bundled:bundled.theme",
            "user:user.theme",
            "ext:com.example.themes/pack.theme"
        ])
        #expect(snapshot.theme(id: "bundled:bundled.theme")?.source == .bundled)
        #expect(snapshot.theme(id: "user:user.theme")?.isEditable == true)
        #expect(snapshot.theme(id: "ext:com.example.themes/pack.theme")?.isEditable == false)
    }

    @Test
    func disabledExtensionPackHidesItsThemes() throws {
        let fixture = try ThemeFixture()
        var preferences = SettingsData()
        preferences.extensions.disabledExtensions = ["com.example.themes"]

        let snapshot = fixture.catalog.load(preferences: preferences)

        #expect(snapshot.themes.map(\.id) == ["bundled:bundled.theme", "user:user.theme"])
    }

    @Test
    func overridesApplyByQualifiedIDAndLegacyName() throws {
        let fixture = try ThemeFixture()
        var preferences = SettingsData()
        preferences.theme.overrides["bundled:bundled.theme"] = [
            "editor": ["background": .init(color: "#010203")]
        ]
        preferences.theme.overrides["user.theme"] = [
            "terminal": ["red": .init(color: "#0A0B0C")]
        ]

        let snapshot = fixture.catalog.load(preferences: preferences)

        #expect(snapshot.theme(id: "bundled:bundled.theme")?.editor.background.color == "#010203")
        #expect(snapshot.theme(id: "user:user.theme")?.terminal.red.color == "#0A0B0C")
    }

    @Test
    func invalidPackThemeIsSkippedAndInvalidUserThemeIsKept() throws {
        let fixture = try ThemeFixture()
        try ThemeFixtures.writeTheme(
            named: "broken",
            color: "#12",
            to: fixture.bundledThemes,
            subdirectory: "themes"
        )
        try ThemeFixtures.writeManifest(
            at: fixture.bundledThemes,
            packID: "com.nodal.default-themes",
            themes: [
                ("bundled.theme", "themes/bundled.theme.cetheme"),
                ("broken", "themes/broken.cetheme")
            ]
        )
        try ThemeFixtures.writeTheme(named: "custom-broken", color: "#12", to: fixture.userThemes)

        let snapshot = fixture.catalog.load(preferences: SettingsData())

        #expect(snapshot.themes.contains { $0.name == "custom-broken" })
        #expect(!snapshot.themes.contains { $0.name == "broken" })
    }

    @Test
    func bundledPackShipsEveryDefaultThemeWithoutAnyExtensionInstalled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ce-theme-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog = ThemeCatalog(
            bundledDirectory: AppSupportLocations.bundledThemesDirectory,
            userDirectory: directory,
            extensionStore: LanguageExtensionStore(
                extensionsDirectory: directory.appending(path: "Extensions", directoryHint: .isDirectory)
            )
        )

        let snapshot = catalog.load(preferences: SettingsData())

        #expect(snapshot.themes.count == 18)
        #expect(snapshot.darkThemes.count == 9)
        #expect(snapshot.lightThemes.count == 9)
        #expect(snapshot.theme(id: "bundled:default.dark")?.name == "default.dark")
        #expect(snapshot.theme(id: "bundled:default.light")?.appearance == .light)
        #expect(snapshot.theme(id: "bundled:high.contrast.dark") != nil)
        #expect(snapshot.theme(id: "bundled:presentation.light") != nil)
        #expect(snapshot.theme(id: "bundled:classic.dark") != nil)
        #expect(snapshot.themes.allSatisfy { $0.source == .bundled })
    }

    @Test
    func legacyNameLookupPrefersUserThemeOverBundledTheme() throws {
        let fixture = try ThemeFixture()
        try ThemeFixtures.writeTheme(named: "bundled.theme", color: "#0A0B0C", to: fixture.userThemes)

        let snapshot = fixture.catalog.load(preferences: SettingsData())

        #expect(snapshot.theme(named: "bundled.theme")?.source == .user)
        #expect(snapshot.theme(id: "bundled:bundled.theme")?.source == .bundled)
    }

    @Test
    func snapshotGroupsThemesByAppearance() throws {
        let fixture = try ThemeFixture()
        let snapshot = fixture.catalog.load(preferences: SettingsData())

        #expect(snapshot.darkThemes.count == 2)
        #expect(snapshot.lightThemes.count == 1)
    }
}

private final class ThemeFixture {
    let root: URL
    let bundledThemes: URL
    let userThemes: URL
    let catalog: ThemeCatalog

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ce-theme-catalog-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundledThemes = root.appending(path: "Bundled", directoryHint: .isDirectory)
        let userThemes = root.appending(path: "User", directoryHint: .isDirectory)
        let extensions = root.appending(path: "Extensions", directoryHint: .isDirectory)
        let pack = extensions.appending(path: "com.example.themes", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: bundledThemes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userThemes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)

        try ThemeFixtures.writeTheme(
            named: "bundled.theme",
            appearance: "dark",
            to: bundledThemes,
            subdirectory: "themes"
        )
        try ThemeFixtures.writeManifest(
            at: bundledThemes,
            packID: "com.nodal.default-themes",
            themes: [("bundled.theme", "themes/bundled.theme.cetheme")]
        )
        try ThemeFixtures.writeTheme(
            named: "pack.theme",
            appearance: "dark",
            to: pack,
            subdirectory: "themes"
        )
        try ThemeFixtures.writeManifest(
            at: pack,
            packID: "com.example.themes",
            themes: [("pack.theme", "themes/pack.theme.cetheme")]
        )
        try ThemeFixtures.writeTheme(named: "user.theme", appearance: "light", to: userThemes)

        self.root = root
        self.bundledThemes = bundledThemes
        self.userThemes = userThemes
        self.catalog = ThemeCatalog(
            bundledDirectory: bundledThemes,
            userDirectory: userThemes,
            extensionStore: LanguageExtensionStore(extensionsDirectory: extensions)
        )
    }
}

private enum ThemeFixtures {
    static func writeTheme(
        named name: String,
        appearance: String = "dark",
        color: String = "#123456",
        to directory: URL,
        subdirectory: String? = nil
    ) throws {
        let target = subdirectory.map {
            directory.appending(path: $0, directoryHint: .isDirectory)
        } ?? directory
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let editorKeys = [
            "text", "insertionPoint", "invisibles", "background", "lineHighlight", "selection",
            "keywords", "commands", "types", "attributes", "variables", "values", "numbers",
            "strings", "characters", "comments"
        ]
        let terminalKeys = [
            "text", "boldText", "cursor", "background", "selection", "black", "red", "green",
            "yellow", "blue", "magenta", "cyan", "white", "brightBlack", "brightRed",
            "brightGreen", "brightYellow", "brightBlue", "brightMagenta", "brightCyan", "brightWhite"
        ]
        let attributes: [String: Any] = ["color": color]
        let document: [String: Any] = [
            "name": name,
            "displayName": name,
            "author": "Tests",
            "version": "1.0.0",
            "type": appearance,
            "editor": Dictionary(uniqueKeysWithValues: editorKeys.map { ($0, attributes) }),
            "terminal": Dictionary(uniqueKeysWithValues: terminalKeys.map { ($0, attributes) })
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted])
        try data.write(to: target.appending(path: "\(name).cetheme"))
    }

    static func writeManifest(at directory: URL, packID: String, themes: [(String, String)]) throws {
        let manifest = LanguageExtensionManifest(
            id: packID,
            name: "Pack \(packID)",
            version: "1.0.0",
            type: "theme",
            capabilities: ["themes"],
            contributes: .init(themes: themes.map { .init(id: $0.0, path: $0.1) })
        )
        try JSONEncoder().encode(manifest).write(to: directory.appending(path: "extension.json"))
    }
}
