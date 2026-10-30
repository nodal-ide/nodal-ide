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
        var isRemovable: Bool { installed?.isRemovable ?? false }
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
    @Published var installXdebug: Bool = true
    @Published private(set) var xdebugStatuses: [String: Bool] = [:]
    @Published private(set) var jobs: [RuntimeJob] = []
    /// php-fpm availability for installed PHP runtimes, keyed by ``InstalledRuntime/id``.
    @Published private(set) var fpmStatuses: [String: PHPFPMStatus] = [:]

    private let manager = AppServices.runtimeManager
    private let fpmCatalog: PHPFPMRuntimeCatalog
    private var cancellables = Set<AnyCancellable>()

    init(detector: (any PHPFPMDetecting)? = nil) {
        self.fpmCatalog = PHPFPMRuntimeCatalog(detector: detector ?? PHPFPMDetector())
        loadDefaults()
        manager.jobs.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] jobs in self?.jobs = jobs }
            .store(in: &cancellables)
    }

    /// The FPM status for an installed PHP row, once detection finishes.
    func fpmStatus(for row: Row) -> PHPFPMStatus? {
        guard let installed = row.installed, selectedKind == .php else {
            return nil
        }
        return fpmStatuses[installed.id]
    }

    func loadFPMStatuses(for runtimes: [InstalledRuntime]) async {
        fpmStatuses = await fpmCatalog.statuses(for: runtimes)
    }

    /// The running install/uninstall job for a version (in the selected kind), if any.
    func runningJob(for version: String) -> RuntimeJob? {
        jobs.first { $0.kind == selectedKind && $0.version == version && $0.status == .running }
    }

    func runningXdebugJob(for row: Row) -> RuntimeJob? {
        guard let runtime = row.installed else { return nil }
        let key = "xdebug@\(runtime.version)"
        return jobs.first { $0.kind == .php && $0.version == key && $0.status == .running }
    }

    func cancel(_ job: RuntimeJob) {
        manager.jobs.cancel(id: job.id)
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

    /// Selected rows that can be uninstalled (managed installs or Homebrew formulae).
    var selectedRemovable: [Row] { selectedRows.filter(\.isRemovable) }

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
        let defaults = AppServices.settings.preferences.developerSettings.defaultRuntimeVersions
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
        if kind == .php {
            await loadFPMStatuses(for: installedList)
            await refreshXdebugStatuses()
        }
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
        let options = PHPInstallOptions(installXdebug: installXdebug)
        for version in versions {
            await manager.install(kind: selectedKind, version: version, phpOptions: options)
        }
        selection.removeAll()
        await load(selectedKind)
    }

    func installXdebug(for row: Row) async {
        guard let runtime = row.installed else { return }
        await manager.installXdebug(for: runtime)
        await load(selectedKind)
        await refreshXdebugStatuses()
    }

    func removeXdebug(from row: Row) async {
        guard let runtime = row.installed else { return }
        await manager.removeXdebug(from: runtime)
        await load(selectedKind)
        await refreshXdebugStatuses()
    }

    func xdebugProvisioned(for row: Row) -> Bool {
        guard let runtime = row.installed else { return false }
        return xdebugStatuses[runtime.id] ?? false
    }

    func refreshXdebugStatuses() async {
        let installed = (rows[.php] ?? []).compactMap(\.installed)
        var statuses: [String: Bool] = [:]
        for runtime in installed {
            statuses[runtime.id] = PHPXdebugProvisioner.shared.isProvisioned(runtime: runtime)
        }
        xdebugStatuses = statuses
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
        var defaults = AppServices.settings.preferences.developerSettings.defaultRuntimeVersions
        if let version, !version.isEmpty {
            defaults[kind.rawValue] = version
        } else {
            defaults.removeValue(forKey: kind.rawValue)
        }
        AppServices.settings.preferences.developerSettings.defaultRuntimeVersions = defaults
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
