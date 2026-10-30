import AppKit
import SwiftUI
import CodeEditSourceEditor
import os

final class ThemeModel: ObservableObject {
    static let shared = ThemeModel()

    private let settingsStore: any SettingsProviding
    private let catalog: ThemeCatalog
    private let fileIO: ThemeFileIO
    private var isRestoringSelection = false
    private var extensionObserver: NSObjectProtocol?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "ThemeModel"
    )

    let filemanager = FileManager.default

    var bundledThemesURL: URL? {
        AppSupportLocations.bundledThemesDirectory
    }

    var themesURL: URL {
        fileIO.userDirectory
    }

    var extensionsURL: URL {
        AppSupportLocations.extensionsDirectory
    }

    var settingsURL: URL {
        AppSupportLocations.settingsFile
    }

    @Published var colorScheme: ColorScheme = .light

    @Published private(set) var palette: ThemePalette = .standard

    @Published var selectedLightTheme: Theme? {
        didSet { persistLightSelection() }
    }

    @Published var selectedDarkTheme: Theme? {
        didSet { persistDarkSelection() }
    }

    @Published var detailsIsPresented: Bool = false

    @Published var isAdding: Bool = false

    @Published var detailsTheme: Theme?

    @Published var themes: [Theme] = []

    @Published var selectedTheme: Theme? {
        didSet {
            refreshPalette()
            persistSelection()
        }
    }

    @Published var previousTheme: Theme?

    var darkThemes: [Theme] {
        themes.filter { $0.appearance == .dark }
    }

    var lightThemes: [Theme] {
        themes.filter { $0.appearance == .light }
    }

    var activeTerminalTheme: Theme? {
        let preferences = settingsStore.preferences
        if preferences.theme.matchAppearance, preferences.terminal.darkAppearance {
            return selectedDarkTheme
        }
        return selectedTheme
    }

    var activeEditorTheme: EditorTheme {
        (selectedTheme ?? themes.first)?.editor.editorTheme ?? Theme.fallback.editor.editorTheme
    }

    init(
        settingsStore: any SettingsProviding = AppServices.settings,
        catalog: ThemeCatalog? = nil,
        fileIO: ThemeFileIO? = nil
    ) {
        self.settingsStore = settingsStore
        let resolvedCatalog = catalog ?? ThemeCatalog()
        self.catalog = resolvedCatalog
        self.fileIO = fileIO ?? ThemeFileIO(userDirectory: resolvedCatalog.userDirectory)
        loadThemes()
        extensionObserver = NotificationCenter.default.addObserver(
            forName: LanguageExtensionManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadThemes()
        }
    }

    deinit {
        if let extensionObserver {
            NotificationCenter.default.removeObserver(extensionObserver)
        }
    }

    func loadThemes() {
        let preferences = settingsStore.preferences
        let snapshot = catalog.load(preferences: preferences)
        themes = snapshot.themes
        restoreSelection(from: snapshot, preferences: preferences)
    }

    private func refreshPalette() {
        palette = ThemeResolver.resolve(selectedTheme ?? Theme.fallback)
    }

    func theme(matching name: String?) -> Theme? {
        guard let name else { return nil }
        if let theme = themes.first(where: { $0.id == name }) {
            return theme
        }
        let matches = themes.filter { $0.name == name || $0.displayName == name }
        return matches.first { $0.source == .user } ?? matches.first
    }

    func updateAppearanceTheme() {
        if selectedTheme?.appearance == .dark {
            selectedDarkTheme = selectedTheme
        } else if selectedTheme?.appearance == .light {
            selectedLightTheme = selectedTheme
        }
    }

    func cancelDetails(_ theme: Theme) {
        guard let index = themes.firstIndex(where: { $0.id == theme.id }),
              let detailsTheme else {
            return
        }
        themes[index] = detailsTheme
        save(themes[index])
    }

    var selectedAppearance: ThemeSettingsAppearances {
        NSApp.effectiveAppearance.name == .darkAqua ? .dark : .light
    }

    enum ThemeSettingsAppearances: String, CaseIterable {
        case light = "Light Appearance"
        case dark = "Dark Appearance"
    }

    func getThemeActive(_ theme: Theme) -> Bool {
        selectedTheme?.id == theme.id
    }

    func activateTheme(_ theme: Theme) {
        selectedTheme = theme
        if colorScheme == .light {
            selectedLightTheme = theme
        }
        if colorScheme == .dark {
            selectedDarkTheme = theme
        }
    }

    func duplicate(_ url: URL) {
        do {
            isAdding = true
            let result = try fileIO.duplicate(url)
            loadThemes()
            guard let index = themes.firstIndex(where: { $0.fileURL == result.url }) else { return }

            let displayName = result.url.deletingPathExtension().lastPathComponent
            themes[index].displayName = displayName
            themes[index].name = displayName.lowercased().replacingOccurrences(of: " ", with: "-")
            if !result.isImporting {
                themes[index].author = NSFullUserName()
                fileIO.save(themes[index])
            }

            previousTheme = selectedTheme
            activateTheme(themes[index])
            detailsTheme = themes[index]
            detailsIsPresented = true
        } catch {
            logger.error("Error adding theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    func rename(to newName: String, theme: Theme) {
        do {
            try fileIO.rename(theme, to: newName)
            loadThemes()
        } catch {
            logger.error("Error renaming theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    func save(_ theme: Theme) {
        fileIO.save(theme)
    }

    func delete(_ theme: Theme) {
        guard theme.isEditable else { return }
        do {
            try fileIO.delete(theme)
            removeOverrides(for: theme)
            loadThemes()
        } catch {
            logger.error("Error deleting theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    func export(_ theme: Theme, to destinationURL: URL) {
        fileIO.export(theme, to: destinationURL)
    }

    func exportAllCustomThemes(to directory: URL) {
        fileIO.exportAllCustomThemes(themes, to: directory)
    }

    private func restoreSelection(from snapshot: ThemeSnapshot, preferences: SettingsData) {
        isRestoringSelection = true
        defer { isRestoringSelection = false }

        let stored = preferences.theme
        let systemIsDark = NSAppearance.currentDrawing().name == .darkAqua
        let fallbackTheme = systemIsDark
            ? snapshot.darkThemes.first ?? snapshot.themes.first
            : snapshot.lightThemes.first ?? snapshot.themes.first

        selectedDarkTheme = snapshot.theme(id: stored.selectedDarkThemeID)
            ?? snapshot.theme(named: stored.selectedDarkTheme)
            ?? snapshot.darkThemes.first
            ?? snapshot.themes.first
        selectedLightTheme = snapshot.theme(id: stored.selectedLightThemeID)
            ?? snapshot.theme(named: stored.selectedLightTheme)
            ?? snapshot.lightThemes.first
            ?? snapshot.themes.first
        selectedTheme = snapshot.theme(id: stored.selectedThemeID)
            ?? snapshot.theme(named: stored.selectedTheme)
            ?? (systemIsDark ? selectedDarkTheme : selectedLightTheme)
            ?? fallbackTheme

        var theme = settingsStore.preferences.theme
        theme.selectedThemeID = selectedTheme?.id
        theme.selectedDarkThemeID = selectedDarkTheme?.id
        theme.selectedLightThemeID = selectedLightTheme?.id
        theme.selectedTheme = selectedTheme?.name
        theme.selectedDarkTheme = selectedDarkTheme?.name ?? theme.selectedDarkTheme
        theme.selectedLightTheme = selectedLightTheme?.name ?? theme.selectedLightTheme
        settingsStore[\.theme] = theme
    }

    private func persistSelection() {
        guard !isRestoringSelection else { return }
        let id = selectedTheme?.id
        let name = selectedTheme?.name
        DispatchQueue.main.async {
            self.settingsStore[\.theme.selectedThemeID] = id
            self.settingsStore[\.theme.selectedTheme] = name
        }
    }

    private func persistDarkSelection() {
        guard !isRestoringSelection else { return }
        let id = selectedDarkTheme?.id
        let name = selectedDarkTheme?.name
        DispatchQueue.main.async {
            self.settingsStore[\.theme.selectedDarkThemeID] = id
            self.settingsStore[\.theme.selectedDarkTheme] = name ?? ""
        }
    }

    private func persistLightSelection() {
        guard !isRestoringSelection else { return }
        let id = selectedLightTheme?.id
        let name = selectedLightTheme?.name
        DispatchQueue.main.async {
            self.settingsStore[\.theme.selectedLightThemeID] = id
            self.settingsStore[\.theme.selectedLightTheme] = name ?? ""
        }
    }

    private func removeOverrides(for theme: Theme) {
        var overrides = settingsStore.preferences.theme.overrides
        overrides.removeValue(forKey: theme.id)
        overrides.removeValue(forKey: theme.name)
        settingsStore[\.theme.overrides] = overrides
    }
}
