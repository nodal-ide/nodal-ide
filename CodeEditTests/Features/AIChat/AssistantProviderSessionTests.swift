@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct AssistantProviderSessionTests {
    @Test
    func sessionUsesSelectedProviderWithoutNetwork() {
        let profile = AssistantProviderProfile(
            name: "LM Studio",
            baseURL: "http://127.0.0.1:1234/v1",
            model: "qwen",
            isLocal: true
        )
        var settings = AssistantSettings()
        settings.profiles = [profile]
        let session = AssistantSession()
        let keychain = InMemoryAssistantKeychainStore()

        session.refreshProviderConfiguration(
            settings: settings,
            keychain: keychain,
            session: URLSession(configuration: .ephemeral)
        )
        session.draft = "Hello"

        #expect(session.provider?.id == profile.id.uuidString)
        #expect(session.provider?.name == "LM Studio")
        #expect(session.provider?.connection == .local)
        #expect(session.provider?.host == "127.0.0.1:1234")
        #expect(session.canSend)
    }

    @Test
    func missingProviderDisablesSending() {
        let session = AssistantSession()
        session.refreshProviderConfiguration(
            settings: AssistantSettings(),
            keychain: InMemoryAssistantKeychainStore(),
            session: URLSession(configuration: .ephemeral)
        )
        session.draft = "Hello"

        #expect(session.provider == nil)
        #expect(!session.canSend)
        #expect(session.destinationLabel == "No provider configured")
    }

    @Test
    func incompleteProfileNeedsSetup() {
        let profile = AssistantProviderProfile(
            name: "Custom",
            baseURL: "https://example.com/v1",
            model: "",
            isLocal: false
        )
        var settings = AssistantSettings()
        settings.profiles = [profile]
        let session = AssistantSession()
        session.refreshProviderConfiguration(
            settings: settings,
            keychain: InMemoryAssistantKeychainStore(),
            session: URLSession(configuration: .ephemeral)
        )
        session.draft = "Hello"

        #expect(session.provider?.connection == .needsSetup)
        #expect(!session.canSend)
    }

    @Test
    func invalidEndpointNeedsSetup() {
        let profile = AssistantProviderProfile(
            name: "Bad",
            baseURL: "http://example.com/v1",
            model: "model",
            isLocal: false
        )
        var settings = AssistantSettings()
        settings.profiles = [profile]
        let session = AssistantSession()
        session.refreshProviderConfiguration(
            settings: settings,
            keychain: InMemoryAssistantKeychainStore(),
            session: URLSession(configuration: .ephemeral)
        )
        session.draft = "Hello"

        #expect(session.provider?.connection == .needsSetup)
        #expect(!session.canSend)
    }

    @Test
    func configurationChangeWaitsUntilStreamingStops() async {
        let session = AssistantSession(
            transport: MockAssistantTransport(chunkDelayNanoseconds: 20_000_000, chunkSize: 2),
            provider: .mock
        )
        session.draft = "Keep streaming"
        session.send()
        await waitForChunk(session)

        let profile = AssistantProviderProfile(
            name: "Ollama",
            baseURL: "http://127.0.0.1:11434/v1",
            model: "llama",
            isLocal: true
        )
        var settings = AssistantSettings()
        settings.profiles = [profile]
        session.refreshProviderConfiguration(
            settings: settings,
            keychain: InMemoryAssistantKeychainStore(),
            session: URLSession(configuration: .ephemeral)
        )

        #expect(session.provider?.id == "mock")

        session.stop()

        #expect(session.provider?.name == "Ollama")
        #expect(session.provider?.connection == .local)
    }

    @Test
    func keychainStoreTrimsEmptyValuesAndRemovesKeys() {
        let store = InMemoryAssistantKeychainStore()
        let id = UUID()

        store.setAPIKey("  token  ", for: id)
        #expect(store.apiKey(for: id) == "token")

        store.setAPIKey("   ", for: id)
        #expect(store.apiKey(for: id) == nil)

        store.setAPIKey("again", for: id)
        store.removeAPIKey(for: id)
        #expect(store.apiKey(for: id) == nil)
    }

    private func waitForChunk(_ session: AssistantSession) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while session.messages.last?.content.isEmpty != false && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.messages.last?.content.isEmpty == false)
    }
}
