import Foundation
import Testing
@testable import CodeEdit

struct NginxTLSConfigurationTests {
    @Test
    func aTLSSiteEmitsASecureServerAndARedirectOnTheInternalPorts() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(tls: NginxTLSSiteConfiguration(
                certificatePath: "/tmp/codeedit/certs/app.localhost.pem",
                privateKeyPath: "/tmp/codeedit/certs/app.localhost-key.pem",
                httpsListenPort: 8443,
                httpListenPort: 8080,
                externalHTTPSPort: 8443
            ))
        )

        #expect(config.contains("listen 127.0.0.1:8443 ssl;"))
        #expect(config.contains("listen [::1]:8443 ssl;"))
        #expect(config.contains("ssl_certificate /tmp/codeedit/certs/app.localhost.pem;"))
        #expect(config.contains("ssl_certificate_key /tmp/codeedit/certs/app.localhost-key.pem;"))
        #expect(config.contains("listen 127.0.0.1:8080;"))
        #expect(config.contains("return 308 https://$host:8443$request_uri;"))
        #expect(!config.contains("listen 127.0.0.1:8080 ssl;"))
    }

    @Test
    func aRedirectForTheDefaultPortOmitsThePort() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(tls: NginxTLSSiteConfiguration(
                certificatePath: "/tmp/codeedit/certs/app.localhost.pem",
                privateKeyPath: "/tmp/codeedit/certs/app.localhost-key.pem",
                httpsListenPort: 18443,
                httpListenPort: 18080,
                externalHTTPSPort: 443
            ))
        )

        #expect(config.contains("return 308 https://$host$request_uri;"))
        #expect(!config.contains("https://$host:443"))
    }

    @Test
    func aPlainSiteHasNoTLSOrRedirect() throws {
        let config = try NginxConfigurationBuilder.siteConfig(site(tls: nil))

        #expect(!config.contains("ssl"))
        #expect(!config.contains("return 308"))
        #expect(config.contains("listen 127.0.0.1:8080;"))
    }

    @Test
    func mainConfigDoesNotAddAPlainDefaultDenyOnTLSPorts() throws {
        let config = try NginxConfigurationBuilder.mainConfig(
            NginxMainConfiguration(
                prefixPath: "/tmp/codeedit/nginx",
                mimeTypesPath: "/tmp/codeedit/nginx/mime.types",
                sitesIncludePath: "/tmp/codeedit/nginx/sites/*.conf",
                pidPath: "/tmp/codeedit/nginx/run/nginx.pid",
                errorLogPath: "/tmp/codeedit/nginx/logs/error.log",
                tempPath: "/tmp/codeedit/nginx/temp",
                listenPorts: [8080, 8443],
                tlsListenPorts: [8443]
            )
        )

        #expect(config.contains("listen 127.0.0.1:8080 default_server;"))
        #expect(!config.contains("listen 127.0.0.1:8443 default_server;"))
        #expect(config.contains("ssl_protocols TLSv1.2 TLSv1.3;"))
    }

    @Test
    func aTLSSiteRejectsAnUnsafeCertificatePath() throws {
        let site = site(tls: NginxTLSSiteConfiguration(
            certificatePath: "/tmp/cer\ntificate.pem",
            privateKeyPath: "/tmp/codeedit/certs/app.localhost-key.pem",
            httpsListenPort: 8443,
            httpListenPort: 8080,
            externalHTTPSPort: 8443
        ))

        #expect(throws: NginxConfigurationError.self) {
            try NginxConfigurationBuilder.siteConfig(site)
        }
    }

    private func site(tls: NginxTLSSiteConfiguration?) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "app.localhost",
            listenPort: 8080,
            documentRootPath: "/tmp/codeedit/roots/app",
            upstream: .staticFiles,
            routing: .directory,
            entryFile: "index.php",
            accessLogPath: "/tmp/codeedit/logs/app.access.log",
            errorLogPath: "/tmp/codeedit/logs/app.error.log",
            tls: tls
        )
    }
}
