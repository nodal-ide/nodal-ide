import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct SystemProcessLauncherTests {
    private let launcher = SystemProcessLauncher()

    private func waitFor(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.timeInterval)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test
    func capturesOutputAndExit() async throws {
        let process = try launcher.launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "echo hello; echo oops 1>&2"]
            )
        )

        let exit = await process.waitForExit()

        #expect(exit.isSuccess)
        #expect(!process.isRunning)
        #expect(process.outputTail.contains(ProcessOutputLine(stream: .stdout, text: "hello")))
        #expect(process.outputTail.contains(ProcessOutputLine(stream: .stderr, text: "oops")))
    }

    @Test
    func reportsPIDForRunningProcessAndStopsCleanly() async throws {
        let process = try launcher.launch(
            ProcessLaunchRequest(executableURL: URL(filePath: "/bin/sleep"), arguments: ["30"])
        )

        #expect(process.isRunning)
        #expect(process.pid > 0)

        await process.stop()

        #expect(!process.isRunning)
        #expect(process.exit != nil)
    }

    @Test
    func stopEscalatesToKillAfterTimeout() async throws {
        let process = try launcher.launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; echo ready; while true; do sleep 0.05; done"]
            )
        )
        let ready = await waitFor { process.outputTail.contains { $0.text == "ready" } }
        #expect(ready)

        await process.stop(signal: ProcessSignal.terminate, timeout: .milliseconds(250))

        #expect(!process.isRunning)
        #expect(process.exit?.reason == .signaled)
        #expect(process.exit?.status == ProcessSignal.kill)
    }

    @Test
    func cancellingAStopStillTerminatesTheProcess() async throws {
        let process = try launcher.launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; echo ready; while true; do sleep 0.05; done"]
            )
        )
        let ready = await waitFor { process.outputTail.contains { $0.text == "ready" } }
        #expect(ready)

        let stopTask = Task {
            await process.stop(signal: ProcessSignal.terminate, timeout: .seconds(30))
        }
        try await Task.sleep(for: .milliseconds(50))
        stopTask.cancel()
        await stopTask.value

        #expect(!process.isRunning)
    }

    @Test
    func outputTailIsBounded() async throws {
        let process = try launcher.launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "i=0; while [ $i -lt 40 ]; do echo line-$i; i=$((i+1)); done"],
                outputLimit: 5
            )
        )

        _ = await process.waitForExit()

        #expect(process.outputTail.count <= 5)
        #expect(process.outputTail.last?.text == "line-39")
    }

    @Test
    func launchFailureThrows() {
        #expect(throws: (any Error).self) {
            try launcher.launch(
                ProcessLaunchRequest(executableURL: URL(filePath: "/nonexistent/binary"))
            )
        }
    }
}
