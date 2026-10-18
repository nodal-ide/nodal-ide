//
//  RunConfigurationStore.swift
//  CodeEdit
//
//  Loads/saves run configurations from `<workspace>/.codeedit/launch.json`.
//

import Combine
import Foundation
import os

@MainActor
final class RunConfigurationStore: ObservableObject {
    @Published private(set) var configurations: [RunConfiguration] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "RunConfigurationStore")

    private let fileURL: URL

    /// The on-disk location of the configurations (`<workspace>/.codeedit/launch.json`).
    var launchFileURL: URL { fileURL }

    init(workspaceURL: URL?) {
        if let workspaceURL {
            fileURL = workspaceURL
                .appending(path: ".codeedit")
                .appending(path: "launch.json")
        } else {
            fileURL = URL(filePath: "/dev/null")
        }
        load()
    }

    // MARK: - CRUD

    func add(_ configuration: RunConfiguration) {
        configurations.append(configuration)
        save()
    }

    func update(_ configuration: RunConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index] = configuration
        save()
    }

    func remove(_ id: UUID) {
        configurations.removeAll { $0.id == id }
        save()
    }

    /// Suggested configurations derived from the workspace's tasks.
    func configurationsFromTasks(_ tasks: [CETask]) -> [RunConfiguration] {
        tasks
            .filter { !$0.isInvalid }
            .map(RunConfiguration.from)
    }

    // MARK: - Persistence

    private func load() {
        guard fileURL.path != "/dev/null" else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            configurations = try JSONDecoder().decode([RunConfiguration].self, from: data)
        } catch {
            logger.error("Failed to load run configurations: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard fileURL.path != "/dev/null" else { return }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configurations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save run configurations: \(error.localizedDescription, privacy: .public)")
        }
    }
}
