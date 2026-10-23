@testable import CodeEdit
import Foundation
import Testing

@Suite
struct AssistantSettingsTests {
    @Test
    func oldSettingsDecodeWithAssistantDefaults() throws {
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8))

        #expect(decoded.assistant.profiles.isEmpty)
        #expect(decoded.assistant.streamResponses)
        #expect(decoded.assistant.temperature == 0.2)
        #expect(decoded.assistant.maxOutputTokens == 2_048)
        #expect(decoded.assistant.contextWindowTokens == 8_192)
        #expect(decoded.assistant.saveHistory)
    }

    @Test
    func offsetProfileDecodesWithDefaults() throws {
        let json = """
        {
          "assistant": {
            "profiles": [
              {
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "name": "Local"
              }
            ]
          }
        }
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
        let profile = try #require(decoded.assistant.profiles.first)

        #expect(profile.name == "Local")
        #expect(profile.baseURL.isEmpty)
        #expect(profile.model.isEmpty)
        #expect(!profile.isLocal)
        #expect(!profile.allowInsecureHTTP)
        #expect(!profile.compatibilityMode)
    }

    @Test
    func malformedProfileDoesNotDropValidProfiles() throws {
        let json = """
        {
          "assistant": {
            "profiles": [
              {
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "name": "Valid"
              },
              "not-a-profile",
              {
                "id": "not-a-uuid",
                "name": "Invalid ID"
              }
            ]
          }
        }
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))

        #expect(decoded.assistant.profiles.count == 1)
        #expect(decoded.assistant.profiles.first?.name == "Valid")
    }

    @Test
    func malformedAssistantSettingsDoNotResetOtherSettings() throws {
        let json = """
        {
          "general": {},
          "assistant": {
            "profiles": "not-an-array",
            "temperature": "hot"
          }
        }
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))

        #expect(decoded.assistant.profiles.isEmpty)
        #expect(decoded.assistant.temperature == 0.2)
    }

    @Test
    func assistantSettingsRoundTripWithoutSecrets() throws {
        let profile = AssistantProviderProfile(
            name: "Remote",
            baseURL: "https://example.com/v1",
            model: "coder",
            isLocal: false,
            allowInsecureHTTP: false,
            compatibilityMode: true
        )
        var settings = SettingsData()
        settings.assistant.profiles = [profile]
        settings.assistant.defaultProfileID = profile.id
        settings.assistant.temperature = 0.7
        settings.assistant.remoteWorkspaceContextConsent[profile.id] = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SettingsData.self, from: data)
        let encoded = try #require(String(data: data, encoding: .utf8))

        #expect(decoded == settings)
        #expect(!encoded.contains("apiKey"))
        #expect(!encoded.contains("secret"))
    }

    @Test
    func defaultProfileFallsBackToFirst() {
        let first = AssistantProviderPreset.lmStudio.makeProfile()
        let second = AssistantProviderPreset.ollama.makeProfile()
        var settings = AssistantSettings()
        settings.profiles = [first, second]

        #expect(settings.defaultProfile == first)

        settings.defaultProfileID = second.id
        #expect(settings.defaultProfile == second)

        settings.defaultProfileID = UUID()
        #expect(settings.defaultProfile == first)
    }

    @Test
    func settingsPageSearchIncludesAssistantKeys() {
        let results = SettingsData().propertiesOf(.assistant)

        #expect(!results.isEmpty)
        #expect(results.contains { $0.settingName == "Provider" })
        #expect(results.allSatisfy { $0.name == .assistant })
    }
}
