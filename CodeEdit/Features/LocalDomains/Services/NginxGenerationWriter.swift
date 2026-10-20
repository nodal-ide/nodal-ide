import Foundation

/// Writes a self-contained nginx generation directory (`nginx.conf`, `mime.types`, `sites/*.conf`).
enum NginxGenerationWriter {
    static func write(
        sites: [NginxSiteConfiguration],
        listenPorts: Set<Int>,
        prefix: NginxPrefix,
        generationName: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = prefix.generationDirectory(named: generationName)
        let sitesDirectory = directory.appending(path: "sites", directoryHint: .isDirectory)

        for target in [directory, sitesDirectory] {
            try fileManager.createDirectory(
                at: target,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let mimeTypesURL = directory.appending(path: "mime.types")
        try NginxMimeTypes.content.write(to: mimeTypesURL, atomically: true, encoding: .utf8)

        for site in sites {
            let url = sitesDirectory.appending(path: "\(site.serverName).conf")
            try NginxConfigurationBuilder.siteConfig(site).write(to: url, atomically: true, encoding: .utf8)
        }

        let mainConfiguration = NginxMainConfiguration(
            prefixPath: prefix.root.path(percentEncoded: false),
            mimeTypesPath: mimeTypesURL.path(percentEncoded: false),
            sitesIncludePath: sitesDirectory.appending(path: "*.conf").path(percentEncoded: false),
            pidPath: prefix.pidURL.path(percentEncoded: false),
            errorLogPath: prefix.errorLogURL.path(percentEncoded: false),
            tempPath: prefix.tempDirectory.path(percentEncoded: false),
            listenPorts: listenPorts,
            tlsListenPorts: Set(sites.compactMap { $0.tls?.httpsListenPort })
        )

        let configURL = directory.appending(path: "nginx.conf")
        try NginxConfigurationBuilder.mainConfig(mainConfiguration)
            .write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    }
}

enum NginxMimeTypes {
    static let content = """
    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        text/plain                            txt;
        application/javascript                js mjs;
        application/json                      json;
        application/xml                       xsl;
        application/pdf                       pdf;
        application/wasm                      wasm;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        image/png                             png;
        image/svg+xml                         svg svgz;
        image/webp                            webp;
        image/x-icon                          ico;
        font/woff                             woff;
        font/woff2                            woff2;
        font/ttf                              ttf;
        font/otf                              otf;
        audio/mpeg                            mp3;
        audio/ogg                             ogg;
        video/mp4                             mp4;
        video/webm                            webm;
    }
    """
}
