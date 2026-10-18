//
//  CEWorkspaceSettingsManager.swift
//  CodeEdit
//
//  Created by Axel Martinez on 27/3/24.
//

import SwiftUI
import Combine
import os

/// The CodeEdit workspace settings model.
final class CEWorkspaceSettings: ObservableObject {
    @Published public var settings: CEWorkspaceSettingsData = .init()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "CEWorkspaceSettings")

    private var storeTask: AnyCancellable?
    private let fileManager = FileManager.default

    private(set) var folderURL: URL

    var settingsURL: URL {
        folderURL.appending(path: "settings").appendingPathExtension("json")
    }

    init(workspaceURL: URL) {
        folderURL = workspaceURL.appending(path: ".codeedit", directoryHint: .isDirectory)
        loadSettings()

        storeTask = $settings
            .receive(on: DispatchQueue.main)
            .throttle(for: 2.0, scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                do {
                    try self.savePreferences()
                } catch {
                    self.logger.error(
                        "Failed to save workspace settings: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
    }

    func cleanUp() {
        storeTask?.cancel()
        storeTask = nil
    }

    deinit {
        cleanUp()
    }

    /// Load and construct ``CEWorkspaceSettings`` model from `.codeedit/settings.json`
    private func loadSettings() {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return }
        do {
            let json = try Data(contentsOf: settingsURL)
            self.settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: json)
        } catch {
            logger.error("Failed to load workspace settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Save``CEWorkspaceSettingsManager`` model to `.codeedit/settings.json`
    func savePreferences() throws {
        // If the user doesn't have any settings to save, don't save them.
        guard !settings.isEmpty() else {
            // Settings is empty, remove the file & directory if it's empty.
            if fileManager.fileExists(atPath: settingsURL.path()) {
                try fileManager.removeItem(at: settingsURL)

                if try fileManager.contentsOfDirectory(atPath: folderURL.path()).isEmpty {
                    try fileManager.removeItem(at: folderURL)
                }
            }
            return
        }

        if !fileManager.fileExists(atPath: folderURL.path()) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let data = try JSONEncoder().encode(settings)
        let json = try JSONSerialization.jsonObject(with: data)
        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try prettyJSON.write(to: settingsURL, options: .atomic)
    }
}
