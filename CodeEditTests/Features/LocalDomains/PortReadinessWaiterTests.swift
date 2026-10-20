import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PortReadinessWaiterTests {
    @Test
    func returnsReadyOnFirstProbe() async {
        let prober = FakePortProber(results: [true])
        let timeSource = FakeTimeSource()
        let waiter = makeWaiter(prober: prober, timeSource: timeSource)

        let result = await waiter.wait(port: 9000, timeout: .seconds(5), isAlive: { true })

        #expect(result == .ready)
        #expect(prober.probedPortNumbers == [9000])
        #expect(timeSource.recordedSleeps.isEmpty)
    }

    @Test
    func backsOffBetweenFailedProbes() async {
        let prober = FakePortProber(results: [false, false, true])
        let timeSource = FakeTimeSource()
        let waiter = makeWaiter(prober: prober, timeSource: timeSource)

        let result = await waiter.wait(port: 9000, timeout: .seconds(5), isAlive: { true })

        #expect(result == .ready)
        #expect(prober.probedPortNumbers.count == 3)
        #expect(timeSource.recordedSleeps == [.milliseconds(50), .milliseconds(100)])
    }

    @Test
    func timesOutAfterTheDeadline() async {
        let prober = FakePortProber(results: [false])
        let timeSource = FakeTimeSource()
        let waiter = makeWaiter(prober: prober, timeSource: timeSource)

        let result = await waiter.wait(port: 9000, timeout: .milliseconds(300), isAlive: { true })

        #expect(result == .timedOut)
        #expect(timeSource.recordedSleeps == [.milliseconds(50), .milliseconds(100), .milliseconds(200)])
    }

    @Test
    func stopsEarlyWhenTheUpstreamExits() async {
        let prober = FakePortProber(results: [false])
        let timeSource = FakeTimeSource()
        let waiter = makeWaiter(prober: prober, timeSource: timeSource)

        let result = await waiter.wait(port: 9000, timeout: .seconds(5), isAlive: { false })

        #expect(result == .upstreamExited)
        #expect(timeSource.recordedSleeps.isEmpty)
    }

    @Test
    func reportsCancellationFromSleep() async {
        let prober = FakePortProber(results: [false])
        let waiter = makeWaiter(prober: prober, timeSource: CancellingTimeSource())

        let result = await waiter.wait(port: 9000, timeout: .seconds(5), isAlive: { true })

        #expect(result == .cancelled)
    }

    private func makeWaiter(prober: FakePortProber, timeSource: any TimeSource) -> PortReadinessWaiter {
        PortReadinessWaiter(
            probe: prober,
            timeSource: timeSource,
            initialDelayMilliseconds: 50,
            maximumDelayMilliseconds: 200
        )
    }
}

private struct CancellingTimeSource: TimeSource {
    var now: Date { Date(timeIntervalSince1970: 0) }

    func sleep(for duration: Duration) async throws {
        throw CancellationError()
    }
}
