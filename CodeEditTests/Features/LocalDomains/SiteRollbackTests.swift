import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct SiteRollbackTests {
    private struct Boom: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    @Test
    func runsRegisteredActionsInReverseOrder() async {
        let rollback = SiteRollback()
        var order: [String] = []

        rollback.register("first") { order.append("first") }
        rollback.register("second") { order.append("second") }
        rollback.register("third") { order.append("third") }

        let failures = await rollback.run()

        #expect(order == ["third", "second", "first"])
        #expect(failures.isEmpty)
        #expect(rollback.isEmpty)
    }

    @Test
    func continuesAfterFailureAndReportsLabel() async {
        let rollback = SiteRollback()
        var order: [String] = []

        rollback.register("first") { order.append("first") }
        rollback.register("second") {
            order.append("second")
            throw Boom()
        }
        rollback.register("third") { order.append("third") }

        let failures = await rollback.run()

        #expect(order == ["third", "second", "first"])
        #expect(failures == [SiteRollback.Failure(label: "second", message: "boom")])
        #expect(rollback.isEmpty)
    }

    @Test
    func resetDropsPendingActions() async {
        let rollback = SiteRollback()
        var ran = false

        rollback.register("only") { ran = true }
        #expect(rollback.count == 1)

        rollback.reset()
        #expect(rollback.isEmpty)

        let failures = await rollback.run()

        #expect(!ran)
        #expect(failures.isEmpty)
    }

    @Test
    func emptyRollbackRunsCleanly() async {
        let rollback = SiteRollback()

        let failures = await rollback.run()

        #expect(failures.isEmpty)
        #expect(rollback.isEmpty)
    }
}
