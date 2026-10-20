import Foundation

enum LocalSiteState: Equatable, Sendable {
    case idle
    case starting
    case running
    case needsRestart
    case stopping
    case error(LocalSiteError)

    var isRunning: Bool {
        self == .running || self == .needsRestart
    }

    var isBusy: Bool {
        self == .starting || self == .stopping
    }

    var failure: LocalSiteError? {
        if case .error(let error) = self {
            return error
        }
        return nil
    }
}

@MainActor
protocol LocalSiteOperations: AnyObject {
    /// Runs the per-project start sequence, registering cleanup for each completed step on `rollback`.
    func start(rollback: SiteRollback) async throws
    func stop() async
    func reload() async throws
}

@MainActor
final class LocalSiteRunner: ObservableObject {
    enum StartResult: Equatable {
        case started
        case alreadyRunning
        case ignoredWhileBusy
        case cancelled
        case failed(LocalSiteError)
    }

    @Published private(set) var state: LocalSiteState = .idle

    private let operations: any LocalSiteOperations
    private let rollback = SiteRollback()

    init(operations: any LocalSiteOperations) {
        self.operations = operations
    }

    @discardableResult
    func start() async -> StartResult {
        switch state {
        case .starting, .stopping:
            return .ignoredWhileBusy
        case .running:
            return .alreadyRunning
        case .idle, .needsRestart, .error:
            break
        }

        rollback.reset()
        state = .starting

        do {
            try await operations.start(rollback: rollback)
        } catch is CancellationError {
            await rollback.run()
            state = .idle
            return .cancelled
        } catch let error as LocalSiteError {
            await rollback.run()
            state = .error(error)
            return .failed(error)
        } catch {
            await rollback.run()
            let wrapped = LocalSiteError.processFailed(error.localizedDescription)
            state = .error(wrapped)
            return .failed(wrapped)
        }

        state = .running
        rollback.reset()
        return .started
    }

    func stop() async {
        switch state {
        case .idle, .starting, .stopping:
            return
        case .running, .needsRestart, .error:
            break
        }

        state = .stopping
        rollback.reset()
        await operations.stop()
        state = .idle
    }

    func markNeedsRestart() {
        guard state == .running else {
            return
        }
        state = .needsRestart
    }

    func reload() async {
        switch state {
        case .running, .needsRestart:
            break
        case .idle, .starting, .stopping, .error:
            return
        }

        do {
            try await operations.reload()
            state = .running
        } catch let error as LocalSiteError {
            state = .error(error)
        } catch {
            state = .error(.processFailed(error.localizedDescription))
        }
    }

    @discardableResult
    func restart() async -> StartResult {
        await stop()
        return await start()
    }
}
