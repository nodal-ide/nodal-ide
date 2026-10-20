import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxControllerIntegrationTests {
    private func site(prefix: NginxPrefix, documentRoot: URL, port: Int) -> NginxSiteConfiguration {
        let accessLog = prefix.logsDirectory.appending(path: "integration.access.log")
        return NginxSiteConfiguration(
            serverName: "integration.localhost",
            listenPort: port,
            documentRootPath: documentRoot.path(percentEncoded: false),
            upstream: .staticFiles,
            routing: .directory,
            entryFile: "index.php",
            accessLogPath: accessLog.path(percentEncoded: false),
            errorLogPath: prefix.errorLogURL.path(percentEncoded: false)
        )
    }

    @Test
    func servesAStaticFileAndStopsCleanly() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()

            let documentRoot = directory.appending(path: "document-root", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
            try "hello-local-domain".write(
                to: documentRoot.appending(path: "index.html"),
                atomically: true,
                encoding: .utf8
            )

            let port = 18127
            let configURL = try NginxGenerationWriter.write(
                sites: [site(prefix: prefix, documentRoot: documentRoot, port: port)],
                listenPorts: [port],
                prefix: prefix,
                generationName: "1"
            )

            let controller = NginxController(prefix: prefix)
            try await controller.start(
                executableURL: nginx.executableURL,
                configURL: configURL,
                listenPorts: [port]
            )

            #expect(controller.isRunning)
            #expect((controller.pid ?? 0) > 0)

            var body: String?
            var fetchError: (any Error)?
            do {
                body = try await Self.fetch(host: "integration.localhost", port: port)
            } catch {
                fetchError = error
            }

            await controller.stop()

            #expect(fetchError == nil)
            #expect(body?.contains("hello-local-domain") == true)
            #expect(!controller.isRunning)
            #expect(controller.pid == nil)
            #expect(controller.state == .stopped)
            let listening = await SocketPortProbe().isReachable(
                host: "127.0.0.1",
                port: port,
                timeout: .milliseconds(200)
            )
            #expect(!listening)
        }
    }

    @Test
    func reloadsANewGenerationWithoutRestartingTheNginxProcess() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()

            let rootOne = try Self.makeDocumentRoot(in: directory, name: "one", body: "generation-one")
            let rootTwo = try Self.makeDocumentRoot(in: directory, name: "two", body: "generation-two")
            let port = 18128
            let controller = NginxController(prefix: prefix)

            var outcome: ReloadOutcome?
            var failure: (any Error)?
            do {
                outcome = try await performReload(
                    controller: controller,
                    nginx: nginx,
                    rootOne: rootOne,
                    rootTwo: rootTwo,
                    port: port
                )
            } catch {
                failure = error
            }

            await controller.stop()

            if let failure {
                throw failure
            }
            #expect(outcome?.initialPID != nil)
            #expect(outcome?.reloadedPID == outcome?.initialPID)
            #expect(outcome?.firstBody?.contains("generation-one") == true)
            #expect(outcome?.secondBody?.contains("generation-two") == true)
            #expect(controller.currentGenerationName == "2")
            #expect(!controller.isRunning)
        }
    }

    private struct ReloadOutcome {
        let initialPID: Int32?
        let reloadedPID: Int32?
        let firstBody: String?
        let secondBody: String?
    }

    private func performReload(
        controller: NginxController,
        nginx: NginxInstallation,
        rootOne: URL,
        rootTwo: URL,
        port: Int
    ) async throws -> ReloadOutcome {
        try await controller.apply(
            executableURL: nginx.executableURL,
            sites: [site(prefix: controller.prefix, documentRoot: rootOne, port: port)],
            listenPorts: [port]
        )
        let initialPID = controller.pid
        let firstBody = await Self.waitForBody(
            host: "integration.localhost",
            port: port,
            contains: "generation-one"
        )

        try await controller.apply(
            executableURL: nginx.executableURL,
            sites: [site(prefix: controller.prefix, documentRoot: rootTwo, port: port)],
            listenPorts: [port]
        )
        let reloadedPID = controller.pid
        let secondBody = await Self.waitForBody(
            host: "integration.localhost",
            port: port,
            contains: "generation-two"
        )

        return ReloadOutcome(
            initialPID: initialPID,
            reloadedPID: reloadedPID,
            firstBody: firstBody,
            secondBody: secondBody
        )
    }

    private static func makeDocumentRoot(in directory: URL, name: String, body: String) throws -> URL {
        let documentRoot = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
        try body.write(to: documentRoot.appending(path: "index.html"), atomically: true, encoding: .utf8)
        return documentRoot
    }

    private static func waitForBody(host: String, port: Int, contains needle: String) async -> String? {
        let deadline = Date().addingTimeInterval(5)
        var lastBody: String?
        while Date() < deadline {
            lastBody = try? await fetch(host: host, port: port)
            if lastBody?.contains(needle) == true {
                return lastBody
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return lastBody
    }

    private static func fetch(host: String, port: Int) async throws -> String? {
        let process = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/curl"),
                arguments: [
                    "-sS", "--fail",
                    "-H", "Host: \(host)",
                    "http://127.0.0.1:\(port)/"
                ],
                outputLimit: 20
            )
        )
        let exit = await process.waitForExit()
        guard exit.isSuccess else {
            return nil
        }
        return process.outputTail.map(\.text).joined(separator: "\n")
    }
}
