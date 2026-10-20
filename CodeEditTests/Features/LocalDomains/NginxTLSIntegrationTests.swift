import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxTLSIntegrationTests {
    @Test
    func servesHTTPSAndRedirectsHTTPToTheCorrectExternalPort() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }

        try await withTempDir { directory in
            let outcome = await Self.roundTrip(directory: directory, nginx: nginx)

            if let failure = outcome.failure {
                throw failure
            }
            #expect(outcome.body?.contains("secured-local-domain") == true)
            #expect(outcome.redirect?.hasPrefix("308 ") == true)
            #expect(outcome.redirect?.contains("https://tls.localhost:\(Self.httpsPort)/") == true)
            #expect(!outcome.isRunning)
        }
    }

    // MARK: - Helpers

    private static let httpsPort = 18144
    private static let httpPort = 18145

    private struct Outcome {
        let body: String?
        let redirect: String?
        let isRunning: Bool
        let failure: (any Error)?
    }

    private struct KeyPaths {
        let certificate: URL
        let key: URL
    }

    private static func roundTrip(directory: URL, nginx: NginxInstallation) async -> Outcome {
        guard let keyPaths = await makeCertificate(in: directory) else {
            return Outcome(body: nil, redirect: nil, isRunning: false, failure: nil)
        }

        let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
        do {
            try prefix.createDirectories()
            let documentRoot = directory.appending(path: "document-root", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
            try "secured-local-domain".write(
                to: documentRoot.appending(path: "index.html"),
                atomically: true,
                encoding: .utf8
            )

            let controller = NginxController(prefix: prefix)
            do {
                try await controller.apply(
                    executableURL: nginx.executableURL,
                    sites: [site(prefix: prefix, documentRoot: documentRoot, keyPaths: keyPaths)],
                    listenPorts: [httpPort, httpsPort]
                )
                let body = try await fetchHTTPS(
                    host: "tls.localhost",
                    port: httpsPort,
                    certificate: keyPaths.certificate
                )
                let redirect = try await fetchRedirect(host: "tls.localhost", port: httpPort)
                await controller.stop()
                return Outcome(body: body, redirect: redirect, isRunning: controller.isRunning, failure: nil)
            } catch {
                await controller.stop()
                return Outcome(body: nil, redirect: nil, isRunning: controller.isRunning, failure: error)
            }
        } catch {
            return Outcome(body: nil, redirect: nil, isRunning: false, failure: error)
        }
    }

    private static func site(
        prefix: NginxPrefix,
        documentRoot: URL,
        keyPaths: KeyPaths
    ) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "tls.localhost",
            listenPort: httpPort,
            documentRootPath: documentRoot.path(percentEncoded: false),
            upstream: .staticFiles,
            routing: .directory,
            entryFile: "index.php",
            accessLogPath: prefix.logsDirectory.appending(path: "tls.access.log").path(percentEncoded: false),
            errorLogPath: prefix.errorLogURL.path(percentEncoded: false),
            tls: NginxTLSSiteConfiguration(
                certificatePath: keyPaths.certificate.path(percentEncoded: false),
                privateKeyPath: keyPaths.key.path(percentEncoded: false),
                httpsListenPort: httpsPort,
                httpListenPort: httpPort,
                externalHTTPSPort: httpsPort
            )
        )
    }

    private static func makeCertificate(in directory: URL) async -> KeyPaths? {
        let certificate = directory.appending(path: "tls.localhost.pem")
        let key = directory.appending(path: "tls.localhost-key.pem")
        let request = ProcessLaunchRequest(
            executableURL: URL(filePath: "/usr/bin/openssl"),
            arguments: [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", key.path(percentEncoded: false),
                "-out", certificate.path(percentEncoded: false),
                "-days", "2",
                "-subj", "/CN=tls.localhost",
                "-addext", "subjectAltName=DNS:tls.localhost",
                "-addext", "basicConstraints=critical,CA:TRUE"
            ],
            outputLimit: 20
        )

        guard let process = try? SystemProcessLauncher().launch(request) else {
            return nil
        }
        let exit = await process.waitForExit()
        guard exit.isSuccess else {
            return nil
        }
        return KeyPaths(certificate: certificate, key: key)
    }

    private static func fetchHTTPS(host: String, port: Int, certificate: URL) async throws -> String? {
        try await runCurl([
            "-sS", "--fail",
            "--cacert", certificate.path(percentEncoded: false),
            "https://\(host):\(port)/"
        ])
    }

    private static func fetchRedirect(host: String, port: Int) async throws -> String? {
        try await runCurl([
            "-sS", "-o", "/dev/null",
            "-w", "%{http_code} %{redirect_url}",
            "-H", "Host: \(host)",
            "http://127.0.0.1:\(port)/"
        ])
    }

    private static func runCurl(_ arguments: [String]) async throws -> String? {
        let process = try SystemProcessLauncher().launch(
            ProcessLaunchRequest(
                executableURL: URL(filePath: "/usr/bin/curl"),
                arguments: arguments,
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
