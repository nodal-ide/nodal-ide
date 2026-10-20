import Foundation
import Testing
@testable import CodeEdit

struct LocalSiteSettingsTests {
    @Test
    func decodesSettingsWithoutSite() throws {
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))

        #expect(settings.site == LocalSiteSettings())
        #expect(settings.site.isEmpty())
    }

    @Test
    func decodesPartialSiteSettings() throws {
        let json = """
        {
          "site": {
            "enabled": true,
            "domain": "my-app.localhost",
            "handler": "proxy",
            "proxy": { "port": 3000 }
          }
        }
        """

        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data(json.utf8))

        #expect(settings.site.enabled)
        #expect(settings.site.domain == "my-app.localhost")
        #expect(settings.site.handler == .proxy)
        #expect(settings.site.proxy.port == 3000)
        #expect(settings.site.proxy.startCommand.isEmpty)
        #expect(settings.site.https)
        #expect(settings.site.routing == .directory)
        #expect(settings.site.entryFile == "index.php")
        #expect(settings.site.phpVersion == nil)
    }

    @Test
    func toleratesUnknownEnums() throws {
        let json = """
        { "site": { "handler": "unknown", "routing": "unknown" } }
        """

        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data(json.utf8))

        #expect(settings.site.handler == .phpFPM)
        #expect(settings.site.routing == .directory)
    }

    @Test
    func emptySiteIsNotEncoded() throws {
        let settings = CEWorkspaceSettingsData()
        let data = try JSONEncoder().encode(settings)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["site"] == nil)
    }

    @Test
    func roundTripsSiteSettings() throws {
        let settings = CEWorkspaceSettingsData()
        settings.site.enabled = true
        settings.site.domain = "my-app.localhost"
        settings.site.handler = .phpFPM
        settings.site.https = false
        settings.site.documentRoot = "public"
        settings.site.routing = .frontController
        settings.site.entryFile = "app.php"
        settings.site.phpVersion = "8.4"
        settings.site.openInBrowser = false
        settings.site.proxy.port = 4000

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: data)

        #expect(decoded.site == settings.site)
        #expect(!decoded.isEmpty())
    }

    @Test
    func emptyProxySectionDoesNotAffectDefaults() throws {
        let json = """
        { "site": { "domain": "my-app.localhost", "proxy": {} } }
        """

        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data(json.utf8))

        #expect(settings.site.proxy == LocalSiteProxySettings())
        #expect(!settings.site.isEmpty())
    }
}
