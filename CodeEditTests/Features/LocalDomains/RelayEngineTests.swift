import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct RelayEngineTests {
    @Test
    func standardConfigurationUsesFixedLoopbackPorts() {
        let configuration = RelayConfiguration.standard
        #expect(configuration.httpListenPort == 80)
        #expect(configuration.httpsListenPort == 443)
        #expect(configuration.httpTargetPort == 18080)
        #expect(configuration.httpsTargetPort == 18443)
    }

    @Test
    func rejectsOutOfRangePorts() {
        let configuration = RelayConfiguration(
            httpListenPort: 0,
            httpTargetPort: 18080,
            httpsListenPort: 443,
            httpsTargetPort: 70000
        )
        #expect(throws: RelayError.invalidPort(0)) {
            try configuration.validate()
        }
    }

    @Test
    func reportsWhenAListenPortIsBusy() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            return
        }
        let port = 18240
        let holder = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/python3"),
                arguments: [
                    "-c",
                    "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',\(port))); "
                    + "s.listen(1); time.sleep(30)"
                ],
                outputLimit: 10
            )
        )
        #expect(await Self.waitForPort(port))

        let engine = RelayEngine(configuration: RelayConfiguration(
            httpListenPort: port,
            httpTargetPort: 18241,
            httpsListenPort: 18242,
            httpsTargetPort: 18243
        ))
        var thrown: (any Error)?
        do {
            try await engine.start()
        } catch {
            thrown = error
        }
        await engine.stop()
        await holder.stop()

        guard case .bindFailed? = thrown as? RelayError else {
            Issue.record("Expected a bind failure, got \(String(describing: thrown))")
            return
        }
    }

    @Test
    func refusesToStartTwice() async throws {
        let engine = RelayEngine(configuration: RelayConfiguration(
            httpListenPort: 18234,
            httpTargetPort: 18235,
            httpsListenPort: 18236,
            httpsTargetPort: 18237
        ))
        try await engine.start()
        await #expect(throws: RelayError.alreadyRunning) {
            try await engine.start()
        }
        await engine.stop()
    }

    @Test
    func forwardsTCPThroughBothListeners() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            return
        }
        try await withTempDir { directory in
            let body = "relay-body"
            try body.write(
                to: directory.appending(path: "index.html"),
                atomically: true,
                encoding: .utf8
            )
            let upstreamPort = 18231
            let upstream = try SystemProcessLauncher().launch(
                ProcessLaunchRequest(
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: [
                        "-m", "http.server", "\(upstreamPort)",
                        "--bind", "127.0.0.1",
                        "--directory", directory.path(percentEncoded: false)
                    ],
                    outputLimit: 50
                )
            )
            #expect(await Self.waitForPort(upstreamPort))

            let engine = RelayEngine(configuration: RelayConfiguration(
                httpListenPort: 18230,
                httpTargetPort: upstreamPort,
                httpsListenPort: 18232,
                httpsTargetPort: upstreamPort
            ))
            var failure: (any Error)?
            var results: [String?] = []
            do {
                try await engine.start()
                results.append(await Self.fetch("http://127.0.0.1:18230/"))
                results.append(await Self.fetch("http://127.0.0.1:18232/"))
                results.append(await Self.fetch("http://[::1]:18230/"))
            } catch {
                failure = error
            }

            await engine.stop()
            await upstream.stop()

            if let failure {
                throw failure
            }
            #expect(results.count == 3)
            #expect(results.allSatisfy { $0?.contains(body) == true })
        }
    }

    private static func fetch(_ url: String) async -> String? {
        guard let process = try? SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/curl"),
                arguments: ["-sS", "--fail", "--max-time", "5", "--noproxy", "*", url],
                outputLimit: 20
            )
        ) else {
            return nil
        }
        let exit = await process.waitForExit()
        guard exit.isSuccess else {
            return nil
        }
        return process.outputTail.map(\.text).joined(separator: "\n")
    }

    private static func waitForPort(_ port: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await SocketPortProbe().isReachable(host: "127.0.0.1", port: port, timeout: .milliseconds(200)) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
