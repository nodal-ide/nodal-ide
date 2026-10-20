import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct LocalSiteRunnerTests {
    @Test
    func startsFromIdle() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        #expect(runner.state == .idle)

        let result = await runner.start()

        #expect(result == .started)
        #expect(runner.state == .running)
        #expect(operations.startCalls == 1)
    }

    @Test
    func startIsIgnoredWhenAlreadyRunning() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        _ = await runner.start()
        let second = await runner.start()

        #expect(second == .alreadyRunning)
        #expect(operations.startCalls == 1)
    }

    @Test
    func startFailureRunsRollbackInReverseOrderAndEntersError() async {
        let operations = FakeLocalSiteOperations()
        operations.startOutcome = .fail(.nginxUnavailable)
        operations.rollbackLabels = ["first", "second", "third"]
        let runner = LocalSiteRunner(operations: operations)

        let result = await runner.start()

        #expect(result == .failed(.nginxUnavailable))
        #expect(runner.state == .error(.nginxUnavailable))
        #expect(operations.executedRollback == ["third", "second", "first"])
    }

    @Test
    func unexpectedStartErrorIsWrappedAsProcessFailure() async {
        let operations = FakeLocalSiteOperations()
        operations.startOutcome = .unexpected(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        )
        let runner = LocalSiteRunner(operations: operations)

        let result = await runner.start()

        #expect(result == .failed(.processFailed("boom")))
        #expect(runner.state == .error(.processFailed("boom")))
    }

    @Test
    func cancelledStartRollsBackAndReturnsToIdle() async {
        let operations = FakeLocalSiteOperations()
        operations.startOutcome = .cancel
        operations.rollbackLabels = ["fpm", "nginx"]
        let runner = LocalSiteRunner(operations: operations)

        let result = await runner.start()

        #expect(result == .cancelled)
        #expect(runner.state == .idle)
        #expect(operations.executedRollback == ["nginx", "fpm"])
    }

    @Test
    func stopMovesRunningSiteToIdle() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        _ = await runner.start()
        await runner.stop()

        #expect(runner.state == .idle)
        #expect(operations.stopCalls == 1)
    }

    @Test
    func stopFromIdleIsANoOp() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        await runner.stop()

        #expect(runner.state == .idle)
        #expect(operations.stopCalls == 0)
    }

    @Test
    func markNeedsRestartOnlyAppliesWhileRunning() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        runner.markNeedsRestart()
        #expect(runner.state == .idle)

        _ = await runner.start()
        runner.markNeedsRestart()
        #expect(runner.state == .needsRestart)
    }

    @Test
    func reloadClearsNeedsRestart() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        _ = await runner.start()
        runner.markNeedsRestart()
        await runner.reload()

        #expect(runner.state == .running)
        #expect(operations.reloadCalls == 1)
    }

    @Test
    func failedReloadEntersError() async {
        let operations = FakeLocalSiteOperations()
        operations.reloadError = LocalSiteError.portInUse(8443)
        let runner = LocalSiteRunner(operations: operations)

        _ = await runner.start()
        runner.markNeedsRestart()
        await runner.reload()

        #expect(runner.state == .error(.portInUse(8443)))
    }

    @Test
    func restartStopsThenStarts() async {
        let operations = FakeLocalSiteOperations()
        let runner = LocalSiteRunner(operations: operations)

        _ = await runner.start()
        let result = await runner.restart()

        #expect(result == .started)
        #expect(runner.state == .running)
        #expect(operations.stopCalls == 1)
        #expect(operations.startCalls == 2)
    }

    @Test
    func stateDerivedProperties() {
        #expect(LocalSiteState.running.isRunning)
        #expect(LocalSiteState.needsRestart.isRunning)
        #expect(!LocalSiteState.idle.isRunning)
        #expect(LocalSiteState.starting.isBusy)
        #expect(LocalSiteState.stopping.isBusy)
        #expect(LocalSiteState.error(.nginxUnavailable).failure == .nginxUnavailable)
        #expect(LocalSiteState.running.failure == nil)
    }
}
