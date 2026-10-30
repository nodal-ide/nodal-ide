import Foundation

enum AppSupportLocations {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nodal", directoryHint: .isDirectory)
    }

    static var settingsFile: URL {
        supportDirectory.appending(path: "settings.json", directoryHint: .isDirectory)
    }

    static var themesDirectory: URL {
        supportDirectory.appending(path: "Themes", directoryHint: .isDirectory)
    }

    static var extensionsDirectory: URL {
        supportDirectory.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    static var bundledThemesDirectory: URL? {
        Bundle.main.resourceURL?.appending(path: "DefaultThemes", directoryHint: .isDirectory)
    }
}
