//
//  Settings.swift
//  CodeEditModules/Settings
//
//  Created by Lukas Pistrol on 01.04.22.
//

import Foundation
import SwiftUI
import Combine
import os

/// The Preferences View Model. Accessible via the singleton "``SettingsModel/shared``".
///
/// **Usage:**
/// ```swift
/// @StateObject
/// private var prefs: SettingsModel = .shared
/// ```
final class Settings: ObservableObject, SettingsProviding {

    /// The publicly available singleton instance of ``SettingsModel``
    static let shared: Settings = .init()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "Settings")

    private var storeTask: AnyCancellable!

    private init() {
        NodalDataMigration.migrateIfNeeded()
        self.preferences = .init()
        self.preferences = loadSettings()

        self.storeTask = self.$preferences.throttle(for: 2, scheduler: RunLoop.main, latest: true).sink { [weak self] in
            guard let self else { return }
            do {
                try self.savePreferences($0)
            } catch {
                self.logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Published instance of the ``Settings`` model.
    ///
    /// Changes are saved automatically.
    @Published var preferences: SettingsData

    /// Load and construct ``Settings`` model from
    /// `~/Library/Application Support/Nodal/settings.json`
    private func loadSettings() -> SettingsData {
        if !filemanager.fileExists(atPath: settingsURL.path) {
            do {
                try filemanager.createDirectory(at: baseURL, withIntermediateDirectories: false)
            } catch {
                logger.error("Failed to create settings directory: \(error.localizedDescription, privacy: .public)")
            }
            return .init()
        }

        do {
            let json = try Data(contentsOf: settingsURL)
            return try JSONDecoder().decode(SettingsData.self, from: json)
        } catch {
            logger.error("Failed to load settings, using defaults: \(error.localizedDescription, privacy: .public)")
            return .init()
        }
    }

    /// Save``Settings`` model to
    /// `~/Library/Application Support/Nodal/settings.json`
    private func savePreferences(_ data: SettingsData) throws {
        let data = try JSONEncoder().encode(data)
        let json = try JSONSerialization.jsonObject(with: data)
        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try prettyJSON.write(to: settingsURL, options: .atomic)
    }

    /// Default instance of the `FileManager`
    private let filemanager = FileManager.default

    /// The base URL of settings.
    ///
    /// Points to `~/Library/Application Support/Nodal/`
    internal var baseURL: URL {
        filemanager
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Nodal", directoryHint: .isDirectory)
    }

    /// The URL of the `settings.json` settings file.
    ///
    /// Points to `~/Library/Application Support/Nodal/settings.json`
    private var settingsURL: URL {
        baseURL
            .appending(path: "settings")
            .appendingPathExtension("json")
    }
}
