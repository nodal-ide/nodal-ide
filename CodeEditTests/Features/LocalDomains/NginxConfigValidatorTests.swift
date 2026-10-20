import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct NginxConfigValidatorTests {
    private func makeSite(prefix: NginxPrefix, documentRoot: URL) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "site-a.localhost",
            listenPort: 18080,
            documentRootPath: documentRoot.path(percentEncoded: false),
            upstream: .staticFiles,
            routing: .directory,
            entryFile: "index.php",
            accessLogPath: prefix.logsDirectory.appending(path: "site-a.access.log").path(percentEncoded: false),
            errorLogPath: prefix.errorLogURL.path(percentEncoded: false)
        )
    }

    @Test
    func validatesAGeneratedGeneration() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()

            let documentRoot = directory.appending(path: "document-root", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)

            let configURL = try NginxGenerationWriter.write(
                sites: [makeSite(prefix: prefix, documentRoot: documentRoot)],
                listenPorts: [18080],
                prefix: prefix,
                generationName: "1"
            )

            let result = await NginxConfigValidator().validate(
                configURL: configURL,
                prefix: prefix,
                executableURL: nginx.executableURL
            )

            #expect(result == .valid)
        }
    }

    @Test
    func rejectsAnInvalidConfigurationWithStderr() async throws {
        guard let nginx = await SystemNginxLocator().locate() else {
            return
        }

        try await withTempDir { directory in
            let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
            try prefix.createDirectories()

            let configURL = prefix.root.appending(path: "broken.conf")
            try "this is not a valid nginx directive {\n".write(
                to: configURL,
                atomically: true,
                encoding: .utf8
            )

            let result = await NginxConfigValidator().validate(
                configURL: configURL,
                prefix: prefix,
                executableURL: nginx.executableURL
            )

            guard case .invalid(let message) = result else {
                Issue.record("Expected nginx -t to reject the configuration.")
                return
            }
            #expect(!message.isEmpty)
            #expect(message.contains("nginx"))
        }
    }
}
