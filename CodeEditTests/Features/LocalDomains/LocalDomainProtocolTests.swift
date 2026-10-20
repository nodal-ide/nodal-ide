import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct LocalDomainProtocolTests {
    @Test
    func timeSourceRecordsSleepsAndAdvances() async throws {
        let clock = FakeTimeSource(now: Date(timeIntervalSince1970: 100))

        try await clock.sleep(for: .seconds(2))
        clock.advance(by: .seconds(3))

        #expect(clock.recordedSleeps == [.seconds(2)])
        #expect(clock.now == Date(timeIntervalSince1970: 105))
    }

    @Test
    func processLauncherReturnsControllableProcess() async throws {
        let launcher = FakeProcessLauncher()
        let request = ProcessLaunchRequest(
            executableURL: URL(filePath: "/usr/bin/true"),
            arguments: ["--version"],
            environment: ["PATH": "/usr/bin"],
            workingDirectory: URL(filePath: "/tmp")
        )

        let process = try #require(launcher.launch(request, onOutput: { _ in }) as? FakeManagedProcess)
        let exit = ProcessExit(status: 0, reason: .exited)
        process.finish(exit)
        let receivedExit = await process.waitForExit()

        #expect(launcher.launches.count == 1)
        #expect(launcher.launches[0].request == request)
        #expect(launcher.outputHandler != nil)
        #expect(process.pid == 1)
        #expect(!process.isRunning)
        #expect(receivedExit == exit)
    }

    @Test
    func processStopRecordsSignalAndTimeout() async throws {
        let launcher = FakeProcessLauncher()
        let process = try #require(
            launcher.launch(
                ProcessLaunchRequest(executableURL: URL(filePath: "/usr/bin/true")),
                onOutput: nil
            ) as? FakeManagedProcess
        )

        await process.stop(signal: ProcessSignal.quit, timeout: .seconds(4))

        #expect(
            process.receivedStops == [
                .init(signal: ProcessSignal.quit, timeout: .seconds(4))
            ]
        )
        #expect(process.exit?.isSuccess == true)
    }

    @Test
    func certificateProviderTracksAuthorityState() async throws {
        let provider = FakeCertificateProvider()

        let initialStatus = await provider.authorityStatus()
        try await provider.trustAuthority()
        let trustedStatus = await provider.authorityStatus()

        #expect(initialStatus == .missing)
        #expect(trustedStatus == .present(trusted: true))
        #expect(provider.trustCalls == 1)
    }

    @Test
    func nginxLocatorReturnsDiscoveredInstallation() async {
        let locator = FakeNginxLocator()
        let installation = NginxInstallation(
            executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
            version: "1.29.4",
            prefixURL: URL(filePath: "/opt/homebrew")
        )
        locator.installation = installation

        let located = await locator.locate()

        #expect(located == installation)
        #expect(locator.locateCalls == 1)
    }
}
