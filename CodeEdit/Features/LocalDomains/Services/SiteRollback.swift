import Foundation

@MainActor
final class SiteRollback {
    struct Failure: Equatable {
        let label: String
        let message: String
    }

    private var steps: [(label: String, action: () async throws -> Void)] = []

    var count: Int {
        steps.count
    }

    var isEmpty: Bool {
        steps.isEmpty
    }

    func register(_ label: String, action: @escaping () async throws -> Void) {
        steps.append((label, action))
    }

    func reset() {
        steps.removeAll()
    }

    @discardableResult
    func run() async -> [Failure] {
        var failures: [Failure] = []

        while let step = steps.popLast() {
            do {
                try await step.action()
            } catch {
                failures.append(Failure(label: step.label, message: error.localizedDescription))
            }
        }

        return failures
    }
}
