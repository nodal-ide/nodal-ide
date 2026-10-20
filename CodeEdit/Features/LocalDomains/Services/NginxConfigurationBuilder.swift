import Foundation

enum NginxUpstream: Equatable, Sendable {
    case staticFiles
    case phpFPM(socketPath: String)
    case proxy(ProxyConfiguration)
}

struct NginxTLSSiteConfiguration: Equatable, Sendable {
    let certificatePath: String
    let privateKeyPath: String
    /// Port nginx listens on for HTTPS (the internal port; `443` only in portless relay mode).
    let httpsListenPort: Int
    /// Port nginx listens on for the plain-HTTP redirect server.
    let httpListenPort: Int
    /// Port the browser uses for HTTPS; drives the redirect target so external ports are correct.
    let externalHTTPSPort: Int
}

struct NginxSiteConfiguration: Equatable, Sendable {
    let serverName: String
    let listenPort: Int
    let documentRootPath: String
    let upstream: NginxUpstream
    let routing: LocalSiteRouting
    let entryFile: String
    let accessLogPath: String
    let errorLogPath: String
    let tls: NginxTLSSiteConfiguration?

    init(
        serverName: String,
        listenPort: Int,
        documentRootPath: String,
        upstream: NginxUpstream,
        routing: LocalSiteRouting,
        entryFile: String,
        accessLogPath: String,
        errorLogPath: String,
        tls: NginxTLSSiteConfiguration? = nil
    ) {
        self.serverName = serverName
        self.listenPort = listenPort
        self.documentRootPath = documentRootPath
        self.upstream = upstream
        self.routing = routing
        self.entryFile = entryFile
        self.accessLogPath = accessLogPath
        self.errorLogPath = errorLogPath
        self.tls = tls
    }
}

struct NginxMainConfiguration: Equatable, Sendable {
    let prefixPath: String
    let mimeTypesPath: String
    let sitesIncludePath: String
    let pidPath: String
    let errorLogPath: String
    let tempPath: String
    /// Every port nginx binds (plain and TLS); used for busy-port checks and validation.
    let listenPorts: Set<Int>
    /// The subset of `listenPorts` that hosts TLS servers and so must not get a plain default-deny.
    let tlsListenPorts: Set<Int>

    init(
        prefixPath: String,
        mimeTypesPath: String,
        sitesIncludePath: String,
        pidPath: String,
        errorLogPath: String,
        tempPath: String,
        listenPorts: Set<Int>,
        tlsListenPorts: Set<Int> = []
    ) {
        self.prefixPath = prefixPath
        self.mimeTypesPath = mimeTypesPath
        self.sitesIncludePath = sitesIncludePath
        self.pidPath = pidPath
        self.errorLogPath = errorLogPath
        self.tempPath = tempPath
        self.listenPorts = listenPorts
        self.tlsListenPorts = tlsListenPorts
    }
}

enum NginxConfigurationError: Error, Equatable, LocalizedError {
    case invalidPath(String)
    case invalidServerName(String)
    case invalidPort(Int)
    case invalidScheme(String)
    case invalidEntryFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "The path is not safe for an nginx config: \(path)."
        case .invalidServerName(let name):
            return "The server name is not valid: \(name)."
        case .invalidPort(let port):
            return "The port is out of range: \(port)."
        case .invalidScheme(let scheme):
            return "The scheme is not supported: \(scheme)."
        case .invalidEntryFile(let file):
            return "The entry file must be a plain PHP filename: \(file)."
        }
    }
}

/// Stateless builders for the app-owned nginx configuration. All paths must be app-controlled
/// (symlinked document roots), so the generated config never contains user-free-form text.
enum NginxConfigurationBuilder {
    static func mainConfig(_ configuration: NginxMainConfiguration) throws -> String {
        try NginxConfigValidation.validate(path: configuration.mimeTypesPath)
        try NginxConfigValidation.validate(path: configuration.sitesIncludePath)
        try NginxConfigValidation.validate(path: configuration.pidPath)
        try NginxConfigValidation.validate(path: configuration.errorLogPath)
        try NginxConfigValidation.validate(path: configuration.tempPath)
        for port in configuration.listenPorts.union(configuration.tlsListenPorts) {
            try NginxConfigValidation.validate(port: port)
        }

        var lines: [String] = [
            "worker_processes 1;",
            "daemon off;",
            "pid \(configuration.pidPath);",
            "error_log \(configuration.errorLogPath) warn;",
            "",
            "events {",
            "    worker_connections 256;",
            "}",
            "",
            "http {",
            "    include \(configuration.mimeTypesPath);",
            "    default_type application/octet-stream;",
            "    server_tokens off;",
            "    access_log off;",
            "    log_format localdomain '$request_method $uri $status $request_time';",
            "",
            "    ssl_protocols TLSv1.2 TLSv1.3;",
            "    ssl_session_cache shared:SSL:1m;",
            "    ssl_session_timeout 10m;",
            "",
            "    client_body_temp_path \(configuration.tempPath)/client_body;",
            "    proxy_temp_path \(configuration.tempPath)/proxy;",
            "    fastcgi_temp_path \(configuration.tempPath)/fastcgi;",
            "    uwsgi_temp_path \(configuration.tempPath)/uwsgi;",
            "    scgi_temp_path \(configuration.tempPath)/scgi;",
            "",
            "    map $http_upgrade $connection_upgrade {",
            "        default upgrade;",
            "        '' close;",
            "    }"
        ]

        for port in configuration.listenPorts.subtracting(configuration.tlsListenPorts).sorted() {
            lines.append("")
            lines.append(contentsOf: defaultDenyServer(port: port))
        }

        lines.append("")
        lines.append("    include \(configuration.sitesIncludePath);")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    static func siteConfig(_ site: NginxSiteConfiguration) throws -> String {
        try NginxConfigValidation.validate(serverName: site.serverName)
        try NginxConfigValidation.validate(path: site.documentRootPath)
        try NginxConfigValidation.validate(path: site.accessLogPath)
        try NginxConfigValidation.validate(path: site.errorLogPath)
        try NginxConfigValidation.validate(port: site.listenPort)
        try NginxConfigValidation.validate(entryFile: site.entryFile)

        if let tls = site.tls {
            try NginxConfigValidation.validate(path: tls.certificatePath)
            try NginxConfigValidation.validate(path: tls.privateKeyPath)
            try NginxConfigValidation.validate(port: tls.httpsListenPort)
            try NginxConfigValidation.validate(port: tls.httpListenPort)
            try NginxConfigValidation.validate(port: tls.externalHTTPSPort)

            let secure = try secureServer(site: site, tls: tls)
            let redirect = redirectServer(site: site, tls: tls)
            return (secure + [""] + redirect).joined(separator: "\n") + "\n"
        }

        return try plainServer(site: site).joined(separator: "\n") + "\n"
    }

    // MARK: - Server blocks

    private static func plainServer(site: NginxSiteConfiguration) throws -> [String] {
        var lines: [String] = [
            "server {",
            "    listen 127.0.0.1:\(site.listenPort);",
            "    listen [::1]:\(site.listenPort);",
            "    server_name \(site.serverName);"
        ]
        lines.append(contentsOf: try sharedLocationLines(site: site))
        lines.append("}")
        return lines
    }

    private static func secureServer(site: NginxSiteConfiguration, tls: NginxTLSSiteConfiguration) throws -> [String] {
        var lines: [String] = [
            "server {",
            "    listen 127.0.0.1:\(tls.httpsListenPort) ssl;",
            "    listen [::1]:\(tls.httpsListenPort) ssl;",
            "    server_name \(site.serverName);",
            "    ssl_certificate \(tls.certificatePath);",
            "    ssl_certificate_key \(tls.privateKeyPath);"
        ]
        lines.append(contentsOf: try sharedLocationLines(site: site))
        lines.append("}")
        return lines
    }

    private static func redirectServer(site: NginxSiteConfiguration, tls: NginxTLSSiteConfiguration) -> [String] {
        let authority = tls.externalHTTPSPort == 443 ? "$host" : "$host:\(tls.externalHTTPSPort)"
        return [
            "server {",
            "    listen 127.0.0.1:\(tls.httpListenPort);",
            "    listen [::1]:\(tls.httpListenPort);",
            "    server_name \(site.serverName);",
            "    return 308 https://\(authority)$request_uri;",
            "}"
        ]
    }

    private static func sharedLocationLines(site: NginxSiteConfiguration) throws -> [String] {
        var lines: [String] = [
            "    root \(site.documentRootPath);",
            "    index index.php index.html;",
            "    access_log \(site.accessLogPath) localdomain;",
            "    error_log \(site.errorLogPath);",
            "",
            "    location ~ /\\.(?!well-known) {",
            "        deny all;",
            "    }"
        ]

        switch site.upstream {
        case .staticFiles:
            lines.append(contentsOf: staticLocation())
        case .phpFPM(let socketPath):
            try NginxConfigValidation.validate(path: socketPath)
            lines.append(contentsOf: phpLocation(site: site, socketPath: socketPath))
        case .proxy(let configuration):
            lines.append(contentsOf: try ProxyConfigurationBuilder.location(configuration))
        }

        return lines
    }

    // MARK: - Blocks

    private static func defaultDenyServer(port: Int) -> [String] {
        [
            "    server {",
            "        listen 127.0.0.1:\(port) default_server;",
            "        listen [::1]:\(port) default_server;",
            "        server_name _;",
            "        return 444;",
            "    }"
        ]
    }

    private static func staticLocation() -> [String] {
        [
            "",
            "    location / {",
            "        try_files $uri $uri/ =404;",
            "    }"
        ]
    }

    private static func phpLocation(site: NginxSiteConfiguration, socketPath: String) -> [String] {
        let tryFiles = site.routing == .frontController
            ? "try_files $uri $uri/ /\(site.entryFile)?$query_string;"
            : "try_files $uri $uri/ =404;"

        var lines: [String] = [
            "",
            "    location / {",
            "        \(tryFiles)",
            "    }",
            "",
            "    location ~ ^(?<script>.+\\.php)(?<info>/.*)$ {",
            "        try_files $script =404;",
            "        fastcgi_split_path_info ^(.+\\.php)(/.*)$;",
            "        # The split capture is set too late for fastcgi_param; snapshot it first.",
            "        set $path_info $fastcgi_path_info;"
        ]
        lines.append(contentsOf: fastcgiParameters(socketPath: socketPath, pathInfo: "$path_info").map {
            "        \($0)"
        })
        lines.append("    }")

        lines.append(contentsOf: [
            "",
            "    location ~ \\.php$ {",
            "        try_files $uri =404;"
        ])
        lines.append(contentsOf: fastcgiParameters(socketPath: socketPath, pathInfo: "$fastcgi_path_info").map {
            "        \($0)"
        })
        lines.append("    }")
        return lines
    }

    private static func fastcgiParameters(socketPath: String, pathInfo: String) -> [String] {
        [
            "fastcgi_pass unix:\(socketPath);",
            "fastcgi_index index.php;",
            "fastcgi_param QUERY_STRING $query_string;",
            "fastcgi_param REQUEST_METHOD $request_method;",
            "fastcgi_param CONTENT_TYPE $content_type;",
            "fastcgi_param CONTENT_LENGTH $content_length;",
            "fastcgi_param SCRIPT_NAME $fastcgi_script_name;",
            "fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;",
            "fastcgi_param PATH_INFO \(pathInfo);",
            "fastcgi_param REQUEST_URI $request_uri;",
            "fastcgi_param DOCUMENT_URI $document_uri;",
            "fastcgi_param DOCUMENT_ROOT $document_root;",
            "fastcgi_param SERVER_PROTOCOL $server_protocol;",
            "fastcgi_param REQUEST_SCHEME $scheme;",
            "fastcgi_param GATEWAY_INTERFACE CGI/1.1;",
            "fastcgi_param SERVER_SOFTWARE nginx/$nginx_version;",
            "fastcgi_param REMOTE_ADDR $remote_addr;",
            "fastcgi_param REMOTE_PORT $remote_port;",
            "fastcgi_param SERVER_ADDR $server_addr;",
            "fastcgi_param SERVER_PORT $server_port;",
            "fastcgi_param SERVER_NAME $server_name;",
            "fastcgi_param REDIRECT_STATUS 200;",
            "fastcgi_param HTTPS $https if_not_empty;"
        ]
    }
}
