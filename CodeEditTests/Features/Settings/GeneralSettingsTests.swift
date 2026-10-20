@testable import CodeEdit
import Testing

@Suite
struct GeneralSettingsTests {
    @Test
    func maximumOpenTabsClampedToSupportedRange() {
        var settings = SettingsData.GeneralSettings()
        #expect(settings.effectiveMaximumOpenTabs == 50)

        settings.maximumOpenTabs = 0
        #expect(settings.effectiveMaximumOpenTabs == 5)

        settings.maximumOpenTabs = 201
        #expect(settings.effectiveMaximumOpenTabs == 200)

        settings.maximumOpenTabs = 75
        #expect(settings.effectiveMaximumOpenTabs == 75)
    }
}
