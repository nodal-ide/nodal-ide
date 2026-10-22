//
//  LanguageExtensionActivation.swift
//  CodeEdit
//
//  Shared activation/enablement rules for declarative language extensions.
//

import Foundation
import CodeEditLang

/// Whether a language extension is enabled and active for a workspace.
///
/// Activation deliberately never scans the project: a declared project language/framework or a
/// literal marker file is enough.
enum LanguageExtensionActivation {
    /// Whether the extension is enabled in settings (extensions are enabled by default).
    static func isEnabled(_ ext: InstalledLanguageExtension) -> Bool {
        !AppServices.settings.preferences.extensions.disabledExtensions.contains(ext.id)
    }

    /// Whether the extension is active in the given workspace.
    static func isActivated(_ ext: InstalledLanguageExtension, in root: URL) -> Bool {
        if let declared = loadProjectSettings(in: root)?.frameworks, !declared.isEmpty {
            guard let name = ext.manifest.frameworkName else { return true }
            return declared.contains { name == $0 || name.contains($0) || $0.contains(name) }
        }

        guard let activation = ext.manifest.activation else { return true }

        if let framework = activation.framework {
            return frameworkMatches(framework, in: root)
        }
        if let files = activation.files, !files.isEmpty {
            return matchesAnyFile(files, in: root)
        }
        return true
    }

    // MARK: - Private

    private static func frameworkMatches(
        _ framework: LanguageExtensionManifest.Activation.Framework,
        in root: URL
    ) -> Bool {
        guard let fileURL = LanguageExtensionPaths.resolve(framework.file ?? "composer.json", in: root),
              LanguageExtensionPaths.isContained(fileURL, in: root) else {
            return false
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        guard let requires = framework.requires, !requires.isEmpty else { return true }
        return requires.keys.contains { content.contains($0) }
    }

    /// Whether any of the (literal, workspace-relative) activation files exist. Wildcards are ignored.
    private static func matchesAnyFile(_ patterns: [String], in root: URL) -> Bool {
        let fileManager = FileManager.default
        return patterns.contains { pattern in
            guard !pattern.contains("*"), !pattern.contains("?"),
                  let url = LanguageExtensionPaths.resolve(pattern, in: root),
                  LanguageExtensionPaths.isContained(url, in: root) else {
                return false
            }
            return fileManager.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    private static func loadProjectSettings(in root: URL) -> ProjectSettings? {
        let url = root.appending(path: ".codeedit/settings.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct ProjectFile: Codable { var project: ProjectSettings? }
        return (try? JSONDecoder().decode(ProjectFile.self, from: data))?.project
    }
}
