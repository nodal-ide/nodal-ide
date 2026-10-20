import Foundation

protocol TimeSource: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemTimeSource: TimeSource {
    var now: Date {
        Date()
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
