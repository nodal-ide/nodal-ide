//
//  LanguageExtensionActivation.swift
//  CodeEdit
//
//  Shared activation/enablement rules for declarative language extensions.
//

import Foundation
import CodeEditLang

/// A project-level override for a globally installed extension.
enum ExtensionActivationOverride: String, Codable, Hashable, Sendable {
    case enabled
    case disabled
}

/// Whether a language extension is enabled and active for a workspace.
///
/// Activation deliberately never scans the project: a declared project language/framework or a
/// literal marker file is enough.
enum LanguageExtensionActivation {
    struct Result: Equatable {
        let reason: Reason

        var isActive: Bool { reason.isActive }
        var explanation: String { reason.explanation }
    }

    enum Reason: Equatable {
        case globallyDisabled
        case disabledForProject
        case enabledForProject
        case declaredProjectWithoutTarget
        case declaredFrameworkMatch(String)
        case declaredFrameworkMismatch(target: String, declared: [String])
        case frameworkFileMatch(file: String, requirement: String?)
        case frameworkFileMissing(file: String)
        case frameworkFileUnreadable(file: String)
        case frameworkRequirementsMissing(file: String, requirements: [String])
        case activationFilePresent(String)
        case activationFilesMissing([String])
        case invalidActivationPath(String)
        case noActivationRules

        var isActive: Bool {
            switch self {
            case .globallyDisabled, .disabledForProject, .declaredFrameworkMismatch,
                 .frameworkFileMissing, .frameworkFileUnreadable, .frameworkRequirementsMissing,
                 .activationFilesMissing, .invalidActivationPath:
                false
            case .enabledForProject, .declaredProjectWithoutTarget, .declaredFrameworkMatch,
                 .frameworkFileMatch, .activationFilePresent, .noActivationRules:
                true
            }
        }

        var explanation: String {
            switch self {
            case .globallyDisabled:
                return "Disabled globally in Extensions settings."
            case .disabledForProject:
                return "Disabled for this project."
            case .enabledForProject:
                return "Enabled for this project by a project override."
            case .declaredProjectWithoutTarget:
                return "The project declares frameworks, and this extension targets no specific framework."
            case .declaredFrameworkMatch(let framework):
                return "The project declares \(framework)."
            case let .declaredFrameworkMismatch(target, declared):
                return "The project declares \(declared.joined(separator: ", ")), not \(target)."
            case let .frameworkFileMatch(file, requirement):
                if let requirement {
                    return "\(file) lists \(requirement)."
                }
                return "\(file) exists."
            case .frameworkFileMissing(let file):
                return "\(file) was not found in the project."
            case .frameworkFileUnreadable(let file):
                return "\(file) could not be read."
            case let .frameworkRequirementsMissing(file, requirements):
                return "\(file) does not list any of: \(requirements.joined(separator: ", "))."
            case .activationFilePresent(let file):
                return "The activation file \(file) exists."
            case .activationFilesMissing(let files):
                return "None of the activation files exist: \(files.joined(separator: ", "))."
            case .invalidActivationPath(let path):
                return "The activation path \(path) is outside the project."
            case .noActivationRules:
                return "No project-specific activation rules; active in every project."
            }
        }
    }

    /// Whether the extension is enabled globally (extensions are enabled by default).
    static func isEnabled(_ ext: InstalledLanguageExtension) -> Bool {
        !AppServices.settings.preferences.extensions.disabledExtensions.contains(ext.id)
    }

    /// Whether the extension is enabled globally and not disabled by a project override.
    static func isEnabled(_ ext: InstalledLanguageExtension, in root: URL) -> Bool {
        guard isEnabled(ext) else { return false }
        return snapshot(for: root).overrides[ext.id] != .disabled
    }

    /// Whether the extension is active for the given project after all scope and manifest rules.
    static func isActivated(_ ext: InstalledLanguageExtension, in root: URL) -> Bool {
        evaluate(ext, in: root).isActive
    }

    /// Evaluates global enablement, project overrides, declared project frameworks, and manifest rules.
    static func evaluate(_ ext: InstalledLanguageExtension, in root: URL) -> Result {
        guard isEnabled(ext) else { return Result(reason: .globallyDisabled) }

        let settings = snapshot(for: root)
        return evaluate(ext, in: root, settings: settings)
    }

    /// Drops the cached project settings for one project root.
    static func invalidate(root: URL) {
        cache.invalidate(root: root)
    }

    /// Drops every cached activation result.
    static func invalidateAll() {
        cache.invalidateAll()
    }

    // MARK: - Manifest rules

    private static func evaluate(
        _ ext: InstalledLanguageExtension,
        in root: URL,
        settings: SettingsSnapshot
    ) -> Result {
        switch settings.overrides[ext.id] {
        case .disabled:
            return Result(reason: .disabledForProject)
        case .enabled:
            return Result(reason: .enabledForProject)
        case nil:
            break
        }

        if !settings.frameworks.isEmpty {
            guard let name = ext.manifest.frameworkName else {
                return Result(reason: .declaredProjectWithoutTarget)
            }
            if let match = settings.frameworks.first(where: {
                name == $0 || name.contains($0) || $0.contains(name)
            }) {
                return Result(reason: .declaredFrameworkMatch(match))
            }
            return Result(
                reason: .declaredFrameworkMismatch(target: name, declared: settings.frameworks)
            )
        }

        guard let activation = ext.manifest.activation else {
            return Result(reason: .noActivationRules)
        }
        if let framework = activation.framework {
            return frameworkResult(framework, in: root)
        }
        if let files = activation.files, !files.isEmpty {
            return activationFileResult(files, in: root)
        }
        return Result(reason: .noActivationRules)
    }

    private static func frameworkResult(
        _ framework: LanguageExtensionManifest.Activation.Framework,
        in root: URL
    ) -> Result {
        let file = framework.file ?? "composer.json"
        guard let fileURL = LanguageExtensionPaths.resolve(file, in: root),
              LanguageExtensionPaths.isContained(fileURL, in: root) else {
            return Result(reason: .invalidActivationPath(file))
        }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return Result(reason: .frameworkFileMissing(file: file))
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return Result(reason: .frameworkFileUnreadable(file: file))
        }
        guard let requires = framework.requires, !requires.isEmpty else {
            return Result(reason: .frameworkFileMatch(file: file, requirement: nil))
        }
        let requirements = requires.keys.sorted()
        if let match = requirements.first(where: { content.contains($0) }) {
            return Result(reason: .frameworkFileMatch(file: file, requirement: match))
        }
        return Result(reason: .frameworkRequirementsMissing(file: file, requirements: requirements))
    }

    /// Whether any of the (literal, workspace-relative) activation files exist. Wildcards are ignored.
    private static func activationFileResult(_ patterns: [String], in root: URL) -> Result {
        let fileManager = FileManager.default
        let literalPatterns = patterns.filter { !$0.contains("*") && !$0.contains("?") }
        guard !literalPatterns.isEmpty else {
            return Result(reason: .activationFilesMissing(patterns))
        }
        var invalidPath: String?
        for pattern in literalPatterns {
            guard let url = LanguageExtensionPaths.resolve(pattern, in: root),
                  LanguageExtensionPaths.isContained(url, in: root) else {
                invalidPath = invalidPath ?? pattern
                continue
            }
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                return Result(reason: .activationFilePresent(pattern))
            }
        }
        if let invalidPath {
            return Result(reason: .invalidActivationPath(invalidPath))
        }
        return Result(reason: .activationFilesMissing(literalPatterns))
    }

    // MARK: - Project settings cache

    private struct SettingsSnapshot {
        let revision: String
        let frameworks: [String]
        let overrides: [String: ExtensionActivationOverride]
    }

    private struct ProjectFile: Decodable {
        struct Project: Decodable {
            var frameworks: [String]?
            var extensionOverrides: [String: ExtensionActivationOverride]?
        }

        var project: Project?
    }

    private static let cache = ActivationCache()

    private static func snapshot(for root: URL) -> SettingsSnapshot {
        let rootKey = root.standardizedFileURL.path(percentEncoded: false)
        let url = URL(filePath: rootKey, directoryHint: .isDirectory)
            .appending(path: ".codeedit/settings.json")
        let revision = settingsRevision(at: url)
        return cache.snapshot(rootKey: rootKey, revision: revision) {
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(ProjectFile.self, from: data) else {
                return SettingsSnapshot(revision: revision, frameworks: [], overrides: [:])
            }
            return SettingsSnapshot(
                revision: revision,
                frameworks: file.project?.frameworks ?? [],
                overrides: file.project?.extensionOverrides ?? [:]
            )
        }
    }

    private static func settingsRevision(at url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        ) else {
            return "missing"
        }
        let modification = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return "\(modification)-\(size)"
    }

    private final class ActivationCache: @unchecked Sendable {
        private let lock = NSLock()
        private var snapshots: [String: SettingsSnapshot] = [:]

        func snapshot(
            rootKey: String,
            revision: String,
            load: () -> SettingsSnapshot
        ) -> SettingsSnapshot {
            lock.lock()
            if let cached = snapshots[rootKey], cached.revision == revision {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let loaded = load()

            lock.lock()
            snapshots[rootKey] = loaded
            lock.unlock()
            return loaded
        }

        func invalidate(root: URL) {
            let rootKey = root.standardizedFileURL.path(percentEncoded: false)
            lock.lock()
            snapshots[rootKey] = nil
            lock.unlock()
        }

        func invalidateAll() {
            lock.lock()
            snapshots.removeAll()
            lock.unlock()
        }
    }
}
