import Foundation
import Testing
@testable import CodeEdit

struct NginxFastCGIConfigurationTests {
    @Test
    func directorySiteSplitsScriptsAndPathInfo() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(routing: .directory, entryFile: "index.php")
        )

        #expect(config.contains("location ~ ^(?<script>.+\\.php)(?<info>/.*)$ {"))
        #expect(config.contains("try_files $script =404;"))
        #expect(config.contains("fastcgi_split_path_info ^(.+\\.php)(/.*)$;"))
        #expect(config.contains("set $path_info $fastcgi_path_info;"))
        #expect(config.contains("fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;"))
        #expect(config.contains("fastcgi_param PATH_INFO $path_info;"))
        #expect(config.contains("fastcgi_param PATH_INFO $fastcgi_path_info;"))
        #expect(config.contains("fastcgi_param DOCUMENT_ROOT $document_root;"))
        #expect(config.contains("fastcgi_pass unix:/tmp/ce-php.sock;"))
    }

    @Test
    func directorySiteReturns404ForMissingFiles() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(routing: .directory, entryFile: "index.php")
        )

        #expect(config.contains("try_files $uri $uri/ =404;"))
        #expect(!config.contains("/index.php?$query_string"))
    }

    @Test
    func frontControllerUsesTheConfiguredEntryFile() throws {
        let config = try NginxConfigurationBuilder.siteConfig(
            site(routing: .frontController, entryFile: "app.php")
        )

        #expect(config.contains("try_files $uri $uri/ /app.php?$query_string;"))
        #expect(!config.contains("/index.php?$query_string"))
        #expect(config.contains("try_files $uri =404;"))
    }

    @Test
    func rejectsUnsafeEntryFiles() {
        for entryFile in ["../../etc/passwd", "index.php;", "index.html", "app.php?x=1", ""] {
            #expect(throws: NginxConfigurationError.invalidEntryFile(entryFile)) {
                try NginxConfigurationBuilder.siteConfig(site(routing: .frontController, entryFile: entryFile))
            }
        }
    }

    private func site(routing: LocalSiteRouting, entryFile: String) -> NginxSiteConfiguration {
        NginxSiteConfiguration(
            serverName: "php.localhost",
            listenPort: 18146,
            documentRootPath: "/tmp/ce-php-root",
            upstream: .phpFPM(socketPath: "/tmp/ce-php.sock"),
            routing: routing,
            entryFile: entryFile,
            accessLogPath: "/tmp/ce-php-access.log",
            errorLogPath: "/tmp/ce-php-error.log"
        )
    }
}
