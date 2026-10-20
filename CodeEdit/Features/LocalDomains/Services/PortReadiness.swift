import Foundation

enum PortReadinessResult: Equatable, Sendable {
    case ready
    case timedOut
    case upstreamExited
    case cancelled
}

/// Waits for a TCP listener with exponential backoff instead of a busy loop. The caller supplies the
/// upstream liveness check so a dev server that exits immediately fails before the full timeout.
@MainActor
struct PortReadinessWaiter {
    let probe: any PortProbing
    let timeSource: any TimeSource
    let host: String
    let initialDelayMilliseconds: Int
    let maximumDelayMilliseconds: Int
    let probeTimeout: Duration

    init(
        probe: any PortProbing = SocketPortProbe(),
        timeSource: any TimeSource = SystemTimeSource(),
        host: String = "127.0.0.1",
        initialDelayMilliseconds: Int = 50,
        maximumDelayMilliseconds: Int = 500,
        probeTimeout: Duration = .milliseconds(250)
    ) {
        self.probe = probe
        self.timeSource = timeSource
        self.host = host
        self.initialDelayMilliseconds = max(1, initialDelayMilliseconds)
        self.maximumDelayMilliseconds = max(initialDelayMilliseconds, maximumDelayMilliseconds)
        self.probeTimeout = probeTimeout
    }

    func wait(
        port: Int,
        timeout: Duration,
        isAlive: @MainActor () -> Bool
    ) async -> PortReadinessResult {
        let deadline = timeSource.now.addingTimeInterval(timeout.timeInterval)
        var delay = initialDelayMilliseconds

        while true {
            if Task.isCancelled {
                return .cancelled
            }
            if await probe.isReachable(host: host, port: port, timeout: probeTimeout) {
                return .ready
            }
            if !isAlive() {
                return .upstreamExited
            }
            if timeSource.now >= deadline {
                return .timedOut
            }
            do {
                try await timeSource.sleep(for: .milliseconds(delay))
            } catch {
                return .cancelled
            }
            delay = min(delay * 2, maximumDelayMilliseconds)
        }
    }
}
