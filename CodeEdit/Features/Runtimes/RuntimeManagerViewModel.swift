//
//  RuntimeManagerViewModel.swift
//  CodeEdit
//
//  Backs the Runtime Manager window (installed/available versions, install, default, packages).
//

import Combine
import Foundation

@MainActor
final class RuntimeManagerViewModel: ObservableObject {
    /// One version row (merged from the catalog and the system).
    struct Row: Identifiable {
        let version: String
        var isLTS: Bool = false
        var releaseDate: Date?
        var installed: InstalledRuntime?
        var available: RuntimeVersion?

        var id: String { version }
        var isInstalled: Bool { installed != nil }
        var isManaged: Bool { installed?.isManaged ?? false }
    }

    @Published var selectedKind: RuntimeKind = .php
    @Published var searchText = ""
    @Published var selection: Set<String> = []

    @Published private(set) var rows: [RuntimeKind: [Row]] = [:]
    @Published private(set) var loading: Set<RuntimeKind> = []
    @Published private(set) var diskUsage: [String: Int64] = [:]
    @Published private(set) var defaultVersions: [RuntimeKind: String] = [:]
    @Published private(set) var packageManagers: [String: String] = [:]
    @Published private(set) var isLoadingPackages = false
    @Published var packageManagerInput = ""

    private let manager = RuntimeManager.shared

    init() {
        loadDefaults()
    }

    // MARK: - Derived

    var currentRows: [Row] {
        let all = rows[selectedKind] ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.version.localizedCaseInsensitiveContains(searchText) }
    }

    var defaultVersion: String? { defaultVersions[selectedKind] }

    func isDefault(_ row: Row) -> Bool { defaultVersions[selectedKind] == row.version }

    /// Selected rows that can be installed (available but not installed).
    var selectedInstallable: [Row] { selectedRows.filter { !$0.isInstalled && $0.available != nil } }

    /// Selected rows that can be uninstalled (installed and managed).
    var selectedRemovable: [Row] { selectedRows.filter(\.isManaged) }

    private var selectedRows: [Row] { currentRows.filter { selection.contains($0.id) } }

    /// The best Node runtime to manage packages for (the default, else the newest installed).
    var nodeRuntime: InstalledRuntime? {
        let installed = (rows[.node] ?? []).compactMap(\.installed)
        if let def = defaultVersions[.node], let match = installed.first(where: { $0.version == def }) {
            return match
        }
        return installed.first
    }

    // MARK: - Loading

    func loadDefaults() {
        let defaults = Settings.shared.preferences.developerSettings.defaultRuntimeVersions
        for kind in RuntimeKind.allCases {
            defaultVersions[kind] = defaults[kind.rawValue]
        }
    }

    func load(_ kind: RuntimeKind) async {
        guard let provider = manager.provider(for: kind) else { return }
        loading.insert(kind)
        async let installed = provider.installedVersions()
        async let available = provider.availableVersions()
        let (installedList, availableList) = await (installed, available)
        rows[kind] = Self.merge(available: availableList, installed: installedList)
        loading.remove(kind)
        await loadDiskUsage(for: installedList)
    }

    func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for kind in RuntimeKind.manageable {
                group.addTask { await self.load(kind) }
            }
        }
        await loadPackageManagers()
    }

    func refreshCurrent() async {
        await load(selectedKind)
        if selectedKind == .node {
            await loadPackageManagers()
        }
    }

    private func loadDiskUsage(for installed: [InstalledRuntime]) async {
        let maxConcurrent = 4
        await withTaskGroup(of: (String, Int64?).self) { group in
            var iterator = installed.makeIterator()
            var running = 0
            while running < maxConcurrent, let runtime = iterator.next() {
                group.addTask { (runtime.id, await RuntimeDiskUsage.size(of: runtime.executableDirectory)) }
                running += 1
            }
            while let (id, size) = await group.next() {
                if let size {
                    diskUsage[id] = size
                }
                if let runtime = iterator.next() {
                    group.addTask { (runtime.id, await RuntimeDiskUsage.size(of: runtime.executableDirectory)) }
                }
            }
        }
    }

    func loadPackageManagers() async {
        guard let runtime = nodeRuntime else {
            packageManagers = [:]
            return
        }
        isLoadingPackages = true
        packageManagers = await manager.nodePackageManagers(for: runtime)
        isLoadingPackages = false
    }

    // MARK: - Actions

    func install(_ rows: [Row]) async {
        let versions = rows.compactMap(\.available)
        guard !versions.isEmpty else { return }
        for version in versions {
            await manager.install(kind: selectedKind, version: version)
        }
        selection.removeAll()
        await load(selectedKind)
    }

    func uninstall(_ rows: [Row]) async {
        let runtimes = rows.compactMap(\.installed)
        guard !runtimes.isEmpty else { return }
        for runtime in runtimes {
            await manager.uninstall(runtime)
        }
        selection.removeAll()
        await load(selectedKind)
    }

    func setDefault(_ version: String?, kind: RuntimeKind) {
        var defaults = Settings.shared.preferences.developerSettings.defaultRuntimeVersions
        if let version, !version.isEmpty {
            defaults[kind.rawValue] = version
        } else {
            defaults.removeValue(forKey: kind.rawValue)
        }
        Settings.shared.preferences.developerSettings.defaultRuntimeVersions = defaults
        defaultVersions[kind] = version
    }

    func activatePackageManager() async {
        let input = packageManagerInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, input.contains("@"), let runtime = nodeRuntime else { return }
        let parts = input.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        await manager.activateNodePackageManager(parts[0], version: parts[1], runtime: runtime)
        packageManagerInput = ""
        await loadPackageManagers()
    }

    // MARK: - Helpers

    private static func merge(available: [RuntimeVersion], installed: [InstalledRuntime]) -> [Row] {
        let installedByVersion = Dictionary(
            installed.map { ($0.version, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var rows = available.map { version in
            Row(
                version: version.version,
                isLTS: version.isLTS ?? false,
                releaseDate: version.releaseDate,
                installed: installedByVersion[version.version],
                available: version
            )
        }
        let known = Set(rows.map(\.version))
        for runtime in installed where !known.contains(runtime.version) {
            rows.append(
                Row(
                    version: runtime.version,
                    installed: runtime,
                    available: nil
                )
            )
        }
        return rows.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}
