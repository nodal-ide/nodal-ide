import Combine
import Foundation

/// Workspace-scoped coordinator that keeps a project's local site in sync with its settings.
///
/// Observes the project's `site` and `runtimes` settings, debounces bursts of edits, diffs the change
/// with ``LocalSiteActionPlanner``, and drives the per-project ``LocalSiteRunner`` with exactly one
/// action per settled change.
@MainActor
final class WorkspaceLocalSiteCoordinator: ObservableObject {
    let workspaceURL: URL

    /// Mirrors the runner's state so status UI can observe the coordinator directly.
    @Published private(set) var state: LocalSiteState

    private let runner: LocalSiteRunner
    private let debounceInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    private var isObservingSettings = false

    private var currentSite: LocalSiteSettings
    private var currentRuntimes: WorkspaceRuntimes

    /// Actions applied so far, in order. Exposed for status UI and tests.
    private(set) var appliedActions: [LocalSiteAction] = []

    init(workspaceURL: URL, runner: LocalSiteRunner, debounceInterval: TimeInterval = 0.5) {
        self.workspaceURL = workspaceURL
        self.runner = runner
        self.debounceInterval = debounceInterval
        self.state = runner.state
        self.currentSite = .init()
        self.currentRuntimes = .init()

        runner.$state
            .sink { [weak self] state in self?.state = state }
            .store(in: &cancellables)
    }

    /// Seeds the current settings and observes the live `site` and `runtimes` publishers.
    func start(settingsManager: CEWorkspaceSettings) {
        guard !isObservingSettings else {
            return
        }
        isObservingSettings = true

        let data = settingsManager.settings
        currentSite = data.site
        currentRuntimes = data.runtimes

        data.$site
            .combineLatest(data.$runtimes)
            .map { SiteObservation(site: $0.0, runtimes: $0.1) }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] observation in
                Task { await self?.apply(site: observation.site, runtimes: observation.runtimes) }
            }
            .store(in: &cancellables)
    }

    /// Diffs against the last applied settings and performs the single resulting action.
    func apply(site: LocalSiteSettings, runtimes: WorkspaceRuntimes) async {
        let action = LocalSiteActionPlanner.action(
            from: currentSite,
            runtimes: currentRuntimes,
            to: site,
            runtimes: runtimes
        )
        currentSite = site
        currentRuntimes = runtimes

        guard action != .none else {
            return
        }

        appliedActions.append(action)
        await perform(action)
    }

    /// Starts an enabled site when the workspace opens, according to the user's preference.
    func startIfEnabledOnOpen(autoStart: Bool) async {
        guard autoStart, currentSite.enabled else {
            return
        }
        await startSite()
    }

    /// Starts the site on demand (status card) and returns once the start sequence settles.
    @discardableResult
    func startSite() async -> LocalSiteRunner.StartResult {
        let result = await runner.start()
        state = runner.state
        return result
    }

    /// Stops the site on demand (status card).
    func stopSite() async {
        await runner.stop()
        state = runner.state
    }

    private func perform(_ action: LocalSiteAction) async {
        switch action {
        case .none:
            return
        case .start:
            await runner.start()
        case .stop:
            await runner.stop()
        case .reloadNginx:
            if runner.state.isRunning {
                await runner.reload()
            } else {
                await runner.restart()
            }
        case .restartFPM, .restartUpstream, .restartAll:
            await runner.restart()
        }
    }

    /// Cancels observation and stops the site. Called when the workspace closes.
    func shutdown() async {
        cancellables.removeAll()
        isObservingSettings = false
        await runner.stop()
        state = runner.state
    }
}

private struct SiteObservation: Equatable {
    let site: LocalSiteSettings
    let runtimes: WorkspaceRuntimes
}
