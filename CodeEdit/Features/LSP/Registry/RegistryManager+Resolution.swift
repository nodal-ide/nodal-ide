//
//  RegistryManager+Resolution.swift
//  CodeEdit
//
//  Resolving a registry item's executable + launch arguments.
//

import Foundation

extension RegistryManager {
    func resolveExecutable(for package: RegistryItem) -> String? {
        guard let method = package.installMethod,
              let manager = method.packageManager(installPath: installPath) else {
            return nil
        }
        let names = executableNames(for: package)

        // npm installs bins into `<installPath>/<package>/node_modules/.bin/<bin>`, and the bin name often
        // differs from the package name (e.g. package `css-lsp` -> bin `vscode-css-language-server`), so the
        // package manager's default path isn't enough.
        if method.packageManagerType == .npm {
            let binDirectory = installPath
                .appending(path: package.name)
                .appending(path: "node_modules")
                .appending(path: ".bin")
            for name in names {
                let candidate = binDirectory.appending(path: name).path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        let base = manager.getBinaryPath(for: package.name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            return base
        }
        for name in names {
            let candidate = URL(filePath: base).appending(path: name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Fall back to the first executable in the directory.
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
        return entries.sorted()
            .map { URL(filePath: base).appending(path: $0).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Launch arguments for a language server.
    ///
    /// Most servers built on `vscode-languageserver` (Node) require `--stdio`; native servers (Rust/Go/C++/…)
    /// default to stdio with **no** arguments and often reject `--stdio`. A per-server override
    /// (`developerSettings.lspServerArguments`) always wins.
    func launchArguments(for package: RegistryItem) -> [String] {
        if let override = Settings.shared.preferences.developerSettings.lspServerArguments[package.name],
           !override.isEmpty {
            return override.split(separator: " ").map(String.init)
        }
        if let known = Self.knownServerArguments[package.name] {
            return known
        }
        return package.installMethod?.packageManagerType == .npm ? ["--stdio"] : []
    }

    /// Servers whose arguments don't follow the npm/native default.
    static let knownServerArguments: [String: [String]] = [
        "bash-language-server": ["start"],
        "pyright": ["--stdio"],
        "basedpyright": ["--stdio"]
    ]

    private func executableNames(for package: RegistryItem) -> [String] {
        var names = package.bin.map { Array($0.keys) } ?? []
        if let last = package.name.components(separatedBy: "/").last {
            names.append(last)
        }
        return names
    }

    /// Fills in missing languages/executable paths for servers installed before these fields existed.
    @MainActor
    func backfillInstalledServers() {
        var changed = false
        let needsWork: (SettingsData.InstalledLanguageServer) -> Bool = {
            $0.executablePath.isEmpty || $0.languages.isEmpty || $0.arguments == nil
        }
        for (name, server) in installedLanguageServers where needsWork(server) {
            guard let item = registryItems.first(where: { $0.name == name }) else { continue }
            var updated = server
            if updated.languages.isEmpty {
                updated.languages = item.languages
            }
            if updated.executablePath.isEmpty {
                updated.executablePath = resolveExecutable(for: item) ?? ""
            }
            if updated.arguments == nil {
                updated.arguments = launchArguments(for: item)
            }
            installedLanguageServers[name] = updated
            changed = true
        }
        if changed {
            reloadLanguageServerConfigs()
        }
    }
}
