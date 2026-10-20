import Foundation
import Testing
@testable import CodeEdit

struct LocalDomainsSettingsTests {
    @Test
    func defaultsAreConservative() {
        let settings = SettingsData.LocalDomainsSettings()

        #expect(settings.portMode == .highPorts)
        #expect(!settings.autoStartSitesOnOpen)
        #expect(!settings.keepNginxRunningWhenIdle)
        #expect(settings.logRetentionBytes == 5 * 1024 * 1024)
        #expect(settings.logRetentionCount == 3)
        #expect(settings.httpsByDefault)
        #expect(settings.openBrowserOnStart)
    }

    @Test
    func missingKeysDecodeToDefaults() throws {
        let settings = try JSONDecoder().decode(
            SettingsData.LocalDomainsSettings.self,
            from: Data("{}".utf8)
        )

        #expect(settings == SettingsData.LocalDomainsSettings())
    }

    @Test
    func invalidValuesAreReplacedOrClamped() throws {
        let json = """
        {
          "portMode": "rootDaemon",
          "autoStartSitesOnOpen": true,
          "keepNginxRunningWhenIdle": true,
          "logRetentionBytes": 1,
          "logRetentionCount": 999,
          "httpsByDefault": false,
          "openBrowserOnStart": false
        }
        """

        let settings = try JSONDecoder().decode(
            SettingsData.LocalDomainsSettings.self,
            from: Data(json.utf8)
        )

        #expect(settings.portMode == .highPorts)
        #expect(settings.autoStartSitesOnOpen)
        #expect(settings.keepNginxRunningWhenIdle)
        #expect(settings.logRetentionBytes == SettingsData.LocalDomainsSettings.minimumLogRetentionBytes)
        #expect(settings.logRetentionCount == SettingsData.LocalDomainsSettings.maximumLogRetentionCount)
        #expect(!settings.httpsByDefault)
        #expect(!settings.openBrowserOnStart)
    }

    @Test
    func mistypedValuesFallBackWithoutDroppingTheRest() throws {
        let json = """
        {"autoStartSitesOnOpen": "yes", "logRetentionBytes": "lots", "httpsByDefault": false}
        """

        let settings = try JSONDecoder().decode(
            SettingsData.LocalDomainsSettings.self,
            from: Data(json.utf8)
        )

        #expect(!settings.autoStartSitesOnOpen)
        #expect(settings.logRetentionBytes == SettingsData.LocalDomainsSettings.defaultLogRetentionBytes)
        #expect(!settings.httpsByDefault)
    }

    @Test
    func roundTripsThroughSettingsData() throws {
        var data = SettingsData()
        data.localDomains.portMode = .privilegedRelay
        data.localDomains.autoStartSitesOnOpen = true
        data.localDomains.logRetentionBytes = 2 * 1024 * 1024
        data.localDomains.logRetentionCount = 5
        data.localDomains.httpsByDefault = false
        data.localDomains.openBrowserOnStart = false

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(SettingsData.self, from: encoded)

        #expect(decoded.localDomains == data.localDomains)
        #expect(decoded.localDomains.portMode == .privilegedRelay)
    }

    @Test
    func settingsDataWithoutLocalDomainsUsesDefaults() throws {
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8))

        #expect(decoded.localDomains == SettingsData.LocalDomainsSettings())
    }
}
