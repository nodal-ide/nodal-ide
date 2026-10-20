import Foundation
import Testing
@testable import CodeEdit

struct NginxConfigurationBuilderTests {
    private func site(
        upstream: NginxUpstream = .staticFiles,
        routing: LocalSiteRouting = .directory,
        documentRootPath: String = "/Users/test/.codeedit/proxy/roots/site-a"
    ) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "site-a.localhost",
            listenPort: 18080,
            documentRootPath: documentRootPath,
            upstream: upstream,
            routing: routing,
            entryFile: "index.php",
            accessLogPath: "/Users/test/.codeedit/proxy/nginx/logs/site-a.access.log",
            errorLogPath: "/Users/test/.codeedit/proxy/nginx/logs/nginx.error.log"
        )
    }

    private func mainConfiguration(listenPorts: Set<Int> = [18080]) -> NginxMainConfiguration {
        NginxMainConfiguration(
            prefixPath: "/Users/test/.codeedit/proxy/nginx",
            mimeTypesPath: "/Users/test/.codeedit/proxy/nginx/mime.types",
            sitesIncludePath: "/Users/test/.codeedit/proxy/nginx/sites/*.conf",
            pidPath: "/Users/test/.codeedit/proxy/nginx/run/nginx.pid",
            errorLogPath: "/Users/test/.codeedit/proxy/nginx/logs/nginx.error.log",
            tempPath: "/Users/test/.codeedit/proxy/nginx/temp",
            listenPorts: listenPorts
        )
    }

    @Test
    func mainConfigIsSelfContainedAndLoopbackOnly() throws {
        let config = try NginxConfigurationBuilder.mainConfig(mainConfiguration())

        #expect(config.contains("worker_processes 1;"))
        #expect(config.contains("include /Users/test/.codeedit/proxy/nginx/mime.types;"))
        #expect(config.contains("include /Users/test/.codeedit/proxy/nginx/sites/*.conf;"))
        #expect(config.contains("listen 127.0.0.1:18080 default_server;"))
        #expect(config.contains("listen [::1]:18080 default_server;"))
        #expect(config.contains("return 444;"))
        #expect(!config.contains("0.0.0.0"))
    }

    @Test
    func staticSiteServesTheDocumentRoot() throws {
        let config = try NginxConfigurationBuilder.siteConfig(site())

        #expect(config.contains("server_name site-a.localhost;"))
        #expect(config.contains("root /Users/test/.codeedit/proxy/roots/site-a;"))
        #expect(config.contains("listen 127.0.0.1:18080;"))
        #expect(config.contains("listen [::1]:18080;"))
        #expect(config.contains("try_files $uri $uri/ =404;"))
        #expect(config.contains("deny all;"))
    }

    @Test
    func frontControllerSiteRewritesToTheEntryFile() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(
                upstream: .phpFPM(socketPath: "/Users/test/.codeedit/proxy/run/site-a.sock"),
                routing: .frontController
            )
        )

        #expect(config.contains("try_files $uri $uri/ /index.php?$query_string;"))
        #expect(config.contains("fastcgi_pass unix:/Users/test/.codeedit/proxy/run/site-a.sock;"))
        #expect(config.contains("fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;"))
    }

    @Test
    func directoryRoutingDoesNotRewriteMissingFiles() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(
                upstream: .phpFPM(socketPath: "/Users/test/.codeedit/proxy/run/site-a.sock"),
                routing: .directory
            )
        )

        #expect(config.contains("try_files $uri $uri/ =404;"))
        #expect(!config.contains("/index.php?$query_string"))
    }

    @Test
    func proxySiteForwardsToLoopbackWithUpgradeHeaders() throws {
        let configuration = ProxyConfiguration(upstreamPort: 3000, externalPort: 8443)
        let config = try NginxConfigurationBuilder.siteConfig(
            site(upstream: .proxy(configuration), routing: .directory)
        )

        #expect(config.contains("proxy_pass http://127.0.0.1:3000;"))
        #expect(config.contains("proxy_http_version 1.1;"))
        #expect(config.contains("proxy_set_header Upgrade $http_upgrade;"))
        #expect(config.contains("proxy_set_header Connection $connection_upgrade;"))
        #expect(config.contains("proxy_set_header X-Forwarded-Port 8443;"))
    }

    @Test
    func rejectsPathsThatCouldInjectConfig() {
        #expect(throws: NginxConfigurationError.self) {
            try NginxConfigurationBuilder.siteConfig(site(documentRootPath: "/tmp/root; include /etc/passwd"))
        }
        #expect(throws: NginxConfigurationError.self) {
            try NginxConfigurationBuilder.siteConfig(site(documentRootPath: "/tmp/root with spaces"))
        }
    }

    @Test
    func rejectsInvalidServerNames() {
        #expect(throws: NginxConfigurationError.self) {
            try NginxConfigurationBuilder.siteConfig(
                NginxSiteConfiguration(
                    serverName: "site-a.localhost; root /etc",
                    listenPort: 18080,
                    documentRootPath: "/tmp/root",
                    upstream: .staticFiles,
                    routing: .directory,
                    entryFile: "index.php",
                    accessLogPath: "/tmp/access.log",
                    errorLogPath: "/tmp/error.log"
                )
            )
        }
    }

    @Test
    func rejectsOutOfRangePorts() {
        #expect(throws: NginxConfigurationError.self) {
            try NginxConfigurationBuilder.siteConfig(
                NginxSiteConfiguration(
                    serverName: "site-a.localhost",
                    listenPort: 70000,
                    documentRootPath: "/tmp/root",
                    upstream: .staticFiles,
                    routing: .directory,
                    entryFile: "index.php",
                    accessLogPath: "/tmp/access.log",
                    errorLogPath: "/tmp/error.log"
                )
            )
        }
    }
}
