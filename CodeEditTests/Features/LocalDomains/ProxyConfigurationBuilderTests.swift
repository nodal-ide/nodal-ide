import Foundation
import Testing
@testable import CodeEdit

struct ProxyConfigurationBuilderTests {
    private func location(
        upstreamPort: Int = 3000,
        externalPort: Int = 8443,
        scheme: String = "http",
        readTimeout: Duration = .seconds(3600),
        buffering: Bool = true
    ) throws -> String {
        try ProxyConfigurationBuilder.location(
            ProxyConfiguration(
                upstreamPort: upstreamPort,
                externalPort: externalPort,
                scheme: scheme,
                readTimeout: readTimeout,
                buffering: buffering
            )
        ).joined(separator: "\n")
    }

    @Test
    func forwardsToTheLoopbackUpstreamOnly() throws {
        let config = try location(upstreamPort: 5173)

        #expect(config.contains("proxy_pass http://127.0.0.1:5173;"))
        #expect(!config.contains("proxy_pass https"))
        #expect(!config.contains("0.0.0.0"))
    }

    @Test
    func forwardsTheBrowserFacingPortAndScheme() throws {
        let config = try location(externalPort: 443, scheme: "https")

        #expect(config.contains("proxy_set_header Host $http_host;"))
        #expect(config.contains("proxy_set_header X-Real-IP $remote_addr;"))
        #expect(config.contains("proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"))
        #expect(config.contains("proxy_set_header X-Forwarded-Host $http_host;"))
        #expect(config.contains("proxy_set_header X-Forwarded-Proto https;"))
        #expect(config.contains("proxy_set_header X-Forwarded-Port 443;"))
    }

    @Test
    func enablesWebSocketUpgrade() throws {
        let config = try location()

        #expect(config.contains("proxy_http_version 1.1;"))
        #expect(config.contains("proxy_set_header Upgrade $http_upgrade;"))
        #expect(config.contains("proxy_set_header Connection $connection_upgrade;"))
    }

    @Test
    func configuresLongTimeoutsInSeconds() throws {
        let config = try location(readTimeout: .seconds(75))

        #expect(config.contains("proxy_connect_timeout 75s;"))
        #expect(config.contains("proxy_send_timeout 75s;"))
        #expect(config.contains("proxy_read_timeout 75s;"))
    }

    @Test
    func disablesBufferingOnlyWhenRequested() throws {
        #expect(try location(buffering: false).contains("proxy_buffering off;"))
        #expect(try !location(buffering: true).contains("proxy_buffering"))
    }

    @Test
    func rejectsUnsafePortsAndSchemes() {
        #expect(throws: NginxConfigurationError.self) {
            try location(upstreamPort: 70000)
        }
        #expect(throws: NginxConfigurationError.self) {
            try location(externalPort: 0)
        }
        #expect(throws: NginxConfigurationError.self) {
            try location(scheme: "gopher")
        }
    }
}
