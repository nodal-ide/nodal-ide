import Combine
import Foundation

@MainActor
final class WorkspaceRuntimeCoordinator {
    private weak var workspace: WorkspaceDocument?
    private var cancellables = Set<AnyCancellable>()

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    func start(settingsManager: CEWorkspaceSettings?) {
        guard let workspace else { return }
        Task { await AppServices.runtimeEnvironment.refresh(workspace: workspace) }

        AppServices.runtimeManager.runtimesDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let workspace = self.workspace else { return }
                Task { await AppServices.runtimeEnvironment.refresh(workspace: workspace) }
            }
            .store(in: &cancellables)

        guard let settingsManager else { return }
        settingsManager.$settings
            .map(\.runtimes)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let workspace = self.workspace else { return }
                Task { await AppServices.runtimeEnvironment.refresh(workspace: workspace) }
            }
            .store(in: &cancellables)
    }
}
