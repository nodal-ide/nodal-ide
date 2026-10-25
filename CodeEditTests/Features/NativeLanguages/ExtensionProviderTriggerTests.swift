@testable import CodeEdit
import Testing

@MainActor
@Suite
struct ExtensionProviderTriggerTests {
    @Test
    func missingTriggersKeepTheLegacyPHPSet() {
        #expect(
            ExtensionLanguageProvider.resolvedCompletionTriggers(nil)
                == ["\\", ">", ":"]
        )
    }

    @Test
    func configuredTriggersReplaceTheLegacySet() {
        #expect(
            ExtensionLanguageProvider.resolvedCompletionTriggers([".", ":", "@"])
                == [".", ":", "@"]
        )
    }

    @Test
    func explicitEmptyTriggersDisableAutomaticCompletion() {
        #expect(ExtensionLanguageProvider.resolvedCompletionTriggers([]).isEmpty)
    }
}
