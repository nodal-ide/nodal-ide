import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxProxyIntegrationTests {
    private static func site(
        prefix: NginxPrefix,
        documentRoot: URL,
        listenPort: Int,
        proxy: ProxyConfiguration
    ) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "proxy.localhost",
            listenPort: listenPort,
            documentRootPath: documentRoot.path(percentEncoded: false),
            upstream: .proxy(proxy),
            routing: .directory,
            entryFile: "index.php",
            accessLogPath: prefix.logsDirectory.appending(path: "proxy.access.log").path(percentEncoded: false),
            errorLogPath: prefix.errorLogURL.path(percentEncoded: false)
        )
    }

    @Test
    func proxiesRequestsToALoopbackUpstream() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()
            let documentRoot = try Self.makeDocumentRoot(in: directory, body: "proxied-body")

            let upstreamPort = 18140
            let nginxPort = 18141
            let upstream = try SystemProcessLauncher().launch(
                ProcessLaunchRequest(
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: [
                        "-m", "http.server", "\(upstreamPort)",
                        "--bind", "127.0.0.1",
                        "--directory", documentRoot.path(percentEncoded: false)
                    ],
                    outputLimit: 50
                )
            )
            #expect(await Self.waitForPort(upstreamPort))

            let controller = NginxController(prefix: prefix)
            let proxy = ProxyConfiguration(upstreamPort: upstreamPort, externalPort: nginxPort)
            var body: String?
            var failure: (any Error)?
            do {
                try await controller.apply(
                    executableURL: nginx.executableURL,
                    sites: [Self.site(prefix: prefix, documentRoot: documentRoot, listenPort: nginxPort, proxy: proxy)],
                    listenPorts: [nginxPort]
                )
                body = await Self.waitForBody(host: "proxy.localhost", port: nginxPort, contains: "proxied-body")
            } catch {
                failure = error
            }

            await controller.stop()
            await upstream.stop()

            if let failure {
                throw failure
            }
            #expect(body?.contains("proxied-body") == true)
        }
    }

    private static func makeDocumentRoot(in directory: URL, body: String) throws -> URL {
        let documentRoot = directory.appending(path: "upstream", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
        try body.write(to: documentRoot.appending(path: "index.html"), atomically: true, encoding: .utf8)
        return documentRoot
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

private struct UpgradeExchange {
    let output: String?
    let captured: String
}

private extension NginxProxyIntegrationTests {
    @Test
    func forwardsWebSocketUpgradeHeaders() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()
            let exchange = try await Self.performUpgrade(
                directory: directory,
                prefix: prefix,
                nginx: nginx,
                upstreamPort: 18148,
                nginxPort: 18149
            )

            #expect(exchange.output?.contains("101") == true)
            #expect(exchange.captured.contains("Upgrade: websocket"))
            #expect(exchange.captured.contains("Connection: upgrade"))
            #expect(exchange.captured.contains("X-Forwarded-Proto: http"))
            #expect(exchange.captured.contains("X-Forwarded-Port: 18149"))
        }
    }

    private static func performUpgrade(
        directory: URL,
        prefix: NginxPrefix,
        nginx: NginxInstallation,
        upstreamPort: Int,
        nginxPort: Int
    ) async throws -> UpgradeExchange {
        let documentRoot = try makeDocumentRoot(in: directory, body: "ws")
        let script = directory.appending(path: "ws_server.py")
        let capture = directory.appending(path: "ws_request.txt")
        try webSocketServerScript.write(to: script, atomically: true, encoding: .utf8)

        let upstream = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/python3"),
                arguments: [
                    script.path(percentEncoded: false),
                    "\(upstreamPort)",
                    capture.path(percentEncoded: false)
                ],
                outputLimit: 50
            )
        )
        #expect(await waitForPort(upstreamPort))

        let controller = NginxController(prefix: prefix)
        let proxy = ProxyConfiguration(upstreamPort: upstreamPort, externalPort: nginxPort)
        var output: String?
        var failure: (any Error)?
        do {
            try await controller.apply(
                executableURL: nginx.executableURL,
                sites: [Self.site(prefix: prefix, documentRoot: documentRoot, listenPort: nginxPort, proxy: proxy)],
                listenPorts: [nginxPort]
            )
            output = await waitForUpgrade(host: "proxy.localhost", port: nginxPort)
        } catch {
            failure = error
        }

        await controller.stop()
        await upstream.stop()

        if let failure {
            throw failure
        }
        let captured = (try? String(contentsOf: capture, encoding: .utf8)) ?? ""
        return UpgradeExchange(output: output, captured: captured)
    }

    private static let webSocketServerScript = #"""
    import socket, sys
    port = int(sys.argv[1])
    capture = sys.argv[2]
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    while True:
        conn, _ = server.accept()
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        if not data:
            conn.close()
            continue
        with open(capture, "wb") as handle:
            handle.write(data)
        conn.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n"
        )
        conn.close()
    """#

    private static func waitForUpgrade(host: String, port: Int) async -> String? {
        let deadline = Date().addingTimeInterval(5)
        var lastOutput: String?
        while Date() < deadline {
            lastOutput = await upgradeRequest(host: host, port: port)
            if lastOutput?.contains("101") == true {
                return lastOutput
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return lastOutput
    }

    private static func upgradeRequest(host: String, port: Int) async -> String? {
        guard let process = try? SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/curl"),
                arguments: [
                    "-sS", "--max-time", "3", "-o", "/dev/null", "-w", "%{http_code}",
                    "-H", "Host: \(host)",
                    "-H", "Connection: Upgrade",
                    "-H", "Upgrade: websocket",
                    "-H", "Sec-WebSocket-Version: 13",
                    "-H", "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
                    "http://127.0.0.1:\(port)/ws"
                ],
                outputLimit: 10
            )
        ) else {
            return nil
        }
        _ = await process.waitForExit()
        return process.outputTail.map(\.text).joined()
    }
}
