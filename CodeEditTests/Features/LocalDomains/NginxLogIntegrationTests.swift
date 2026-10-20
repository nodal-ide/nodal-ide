import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxLogIntegrationTests {
    private func site(prefix: NginxPrefix, documentRoot: URL, port: Int, accessLog: URL) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "logs.localhost",
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
    func rotationKeepsNginxWritingToAReopenedLog() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()
            let documentRoot = try Self.makeDocumentRoot(in: directory)
            let accessLog = prefix.logsDirectory.appending(path: "logs.access.log")
            let port = 18142
            let controller = NginxController(prefix: prefix)

            var rotatedBackup = false
            var wroteAfterRotation = false
            var failure: (any Error)?

            do {
                try await controller.apply(
                    executableURL: nginx.executableURL,
                    sites: [site(prefix: prefix, documentRoot: documentRoot, port: port, accessLog: accessLog)],
                    listenPorts: [port]
                )
                _ = try await Self.fetch(host: "logs.localhost", port: port)
                #expect(await Self.waitForContent(accessLog))

                let rotated = try controller.rotateLogs([accessLog], maxBytes: 0)
                rotatedBackup = rotated == [accessLog]
                    && FileManager.default.fileExists(atPath: accessLog.path(percentEncoded: false) + ".1")

                _ = try await Self.fetch(host: "logs.localhost", port: port)
                wroteAfterRotation = await Self.waitForContent(accessLog)
            } catch {
                failure = error
            }

            await controller.stop()

            if let failure {
                throw failure
            }
            #expect(rotatedBackup)
            #expect(wroteAfterRotation)
            let tail = try LogFileTail.lines(at: accessLog, maxLines: 5)
            #expect(!tail.isEmpty)
            #expect(tail.allSatisfy { $0.contains("GET") })
        }
    }

    private static func makeDocumentRoot(in directory: URL) throws -> URL {
        let documentRoot = directory.appending(path: "document-root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
        try "log-body".write(to: documentRoot.appending(path: "index.html"), atomically: true, encoding: .utf8)
        return documentRoot
    }

    private static func waitForContent(_ url: URL) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            if let size = attributes?[.size] as? Int, size > 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private static func fetch(host: String, port: Int) async throws -> String? {
        let process = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/curl"),
                arguments: ["-sS", "--fail", "-H", "Host: \(host)", "http://127.0.0.1:\(port)/"],
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
