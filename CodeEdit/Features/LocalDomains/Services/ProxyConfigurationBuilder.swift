import Foundation

struct ProxyConfiguration: Equatable, Sendable {
    let upstreamPort: Int
    let externalPort: Int
    let scheme: String
    let readTimeout: Duration
    let buffering: Bool

    init(
        upstreamPort: Int,
        externalPort: Int,
        scheme: String = "http",
        readTimeout: Duration = .seconds(3600),
        buffering: Bool = true
    ) {
        self.upstreamPort = upstreamPort
        self.externalPort = externalPort
        self.scheme = scheme
        self.readTimeout = readTimeout
        self.buffering = buffering
    }

    /// The loopback upstream nginx talks to; never user-controlled host/scheme.
    var upstreamAddress: String {
        "http://127.0.0.1:\(upstreamPort)"
    }
}

/// Builds the reverse-proxy `location /` block: loopback upstream, forwarded headers including the
/// browser-facing `X-Forwarded-Port`/`X-Forwarded-Proto`, WebSocket upgrade, and long read timeouts.
enum ProxyConfigurationBuilder {
    static func location(_ configuration: ProxyConfiguration) throws -> [String] {
        try NginxConfigValidation.validate(port: configuration.upstreamPort)
        try NginxConfigValidation.validate(port: configuration.externalPort)
        guard configuration.scheme == "http" || configuration.scheme == "https" else {
            throw NginxConfigurationError.invalidScheme(configuration.scheme)
        }

        let timeout = max(1, Int(configuration.readTimeout.timeInterval))
        var lines: [String] = [
            "",
            "    location / {",
            "        proxy_pass \(configuration.upstreamAddress);",
            "        proxy_http_version 1.1;",
            "        proxy_set_header Host $http_host;",
            "        proxy_set_header X-Real-IP $remote_addr;",
            "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
            "        proxy_set_header X-Forwarded-Host $http_host;",
            "        proxy_set_header X-Forwarded-Proto \(configuration.scheme);",
            "        proxy_set_header X-Forwarded-Port \(configuration.externalPort);",
            "        proxy_set_header Upgrade $http_upgrade;",
            "        proxy_set_header Connection $connection_upgrade;",
            "        proxy_connect_timeout \(timeout)s;",
            "        proxy_send_timeout \(timeout)s;",
            "        proxy_read_timeout \(timeout)s;"
        ]
        if !configuration.buffering {
            lines.append("        proxy_buffering off;")
        }
        lines.append("    }")
        return lines
    }
}

/// Shared, stateless validation for values interpolated into nginx configs. All interpolated values are
/// app-controlled; these guards keep that invariant enforced at the boundary.
enum NginxConfigValidation {
    static func validate(port: Int) throws {
        guard (1...65535).contains(port) else {
            throw NginxConfigurationError.invalidPort(port)
        }
    }

    static func validate(serverName: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !serverName.isEmpty, serverName.unicodeScalars.allSatisfy(allowed.contains) else {
            throw NginxConfigurationError.invalidServerName(serverName)
        }
    }

    static func validate(path: String) throws {
        guard !path.isEmpty else {
            throw NginxConfigurationError.invalidPath(path)
        }
        let forbidden = CharacterSet(charactersIn: " \t\n\r\"'`;{}$#\\")
        guard path.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw NginxConfigurationError.invalidPath(path)
        }
    }

    static func validate(entryFile: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !entryFile.isEmpty,
              !entryFile.contains(".."),
              entryFile.lowercased().hasSuffix(".php"),
              entryFile.unicodeScalars.allSatisfy(allowed.contains) else {
            throw NginxConfigurationError.invalidEntryFile(entryFile)
        }
    }
}
