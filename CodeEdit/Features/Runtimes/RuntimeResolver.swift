//
//  RuntimeResolver.swift
//  CodeEdit
//
//  Resolves which runtime to use for a project: project pin → global default → newest installed.
//

import Foundation

@MainActor
enum RuntimeResolver {
    /// Resolves the installed runtime for a project.
    static func resolve(kind: RuntimeKind, workspace: WorkspaceDocument?) async -> InstalledRuntime? {
        let installed = await RuntimeManager.shared.provider(for: kind)?.installedVersions() ?? []
        guard !installed.isEmpty else { return nil }

        if let pinned = projectPinnedVersion(kind: kind, workspace: workspace),
           let match = match(pinned, in: installed) {
            return match
        }
        if let global = AppServices.settings.preferences.developerSettings.defaultRuntimeVersions[kind.rawValue],
           let match = match(global, in: installed) {
            return match
        }
        return installed.first
    }

    /// The version pinned by the project settings, or an ecosystem file (`.nvmrc`/`.php-version`).
    static func projectPinnedVersion(kind: RuntimeKind, workspace: WorkspaceDocument?) -> String? {
        if let version = workspace?.workspaceSettingsManager?.settings.runtimes.selection(for: kind).version,
           !version.isEmpty {
            return version
        }
        guard let root = workspace?.fileURL else { return nil }
        switch kind {
        case .node:
            return readTrimmed(root.appending(path: ".nvmrc"))?.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        case .php:
            return readTrimmed(root.appending(path: ".php-version"))
        case .typescript:
            return nil
        }
    }

    /// Writes an ecosystem pin file for the given version, if the ecosystem supports it.
    static func writeEcosystemPin(kind: RuntimeKind, workspace: WorkspaceDocument?, version: String) {
        guard let root = workspace?.fileURL else { return }
        switch kind {
        case .node:
            try? version.write(to: root.appending(path: ".nvmrc"), atomically: true, encoding: .utf8)
        case .php:
            try? version.write(to: root.appending(path: ".php-version"), atomically: true, encoding: .utf8)
        case .typescript:
            break
        }
    }

    // MARK: - Helpers

    private static func match(_ version: String, in installed: [InstalledRuntime]) -> InstalledRuntime? {
        if let exact = installed.first(where: { $0.version == version }) {
            return exact
        }
        // Fall back to the same major.minor (e.g. a "8.1.34" pin matches an installed "8.1.31").
        let minor = minorVersion(version)
        return installed.first { minorVersion($0.version) == minor }
    }

    private static func minorVersion(_ version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    private static func readTrimmed(_ url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
