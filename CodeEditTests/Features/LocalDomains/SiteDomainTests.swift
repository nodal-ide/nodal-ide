import Foundation
import Testing
@testable import CodeEdit

struct SiteDomainTests {
    @Test
    func normalizesDomains() throws {
        #expect(try SiteDomain("my-app").value == "my-app.localhost")
        #expect(try SiteDomain("  My-App.LOCALHOST  ").value == "my-app.localhost")
        #expect(try SiteDomain("docs.api.localhost").value == "docs.api.localhost")
        #expect(try SiteDomain("my-app.localhost.").value == "my-app.localhost")
    }

    @Test
    func rejectsInvalidDomains() {
        expectInvalid("", .empty)
        expectInvalid("   ", .empty)
        expectInvalid(".localhost", .missingLabel)
        expectInvalid("foo..localhost", .emptyLabel)
        expectInvalid("-foo.localhost", .invalidLabel)
        expectInvalid("foo-.localhost", .invalidLabel)
        expectInvalid("foo_bar.localhost", .invalidCharacters)
        expectInvalid("foo/bar.localhost", .invalidCharacters)
        expectInvalid("foo.com", .unsupportedSuffix)
        expectInvalid("café.localhost", .invalidCharacters)
        expectInvalid(String(repeating: "a", count: 64) + ".localhost", .labelTooLong)
    }

    @Test
    func rejectsLongDomains() {
        let label = String(repeating: "a", count: 63)
        let domain = [label, label, label, label, "localhost"].joined(separator: ".")
        expectInvalid(domain, .domainTooLong)
    }

    @Test
    func suggestsFromProjectName() throws {
        #expect(SiteDomain.suggested(from: "My App!").value == "my-app.localhost")
        #expect(SiteDomain.suggested(from: "--My App--").value == "my-app.localhost")
        #expect(SiteDomain.suggested(from: "Café").value == "cafe.localhost")
        #expect(SiteDomain.suggested(from: "").value == "project.localhost")
    }

    @Test
    func suggestsUniqueDomain() throws {
        let existing: Set<SiteDomain> = [
            try SiteDomain("my-app.localhost"),
            try SiteDomain("my-app-2.localhost")
        ]

        #expect(SiteDomain.suggested(from: "My App", existingDomains: existing).value == "my-app-3.localhost")
    }

    @Test
    func truncatesSuggestions() {
        let longName = String(repeating: "a", count: 80)
        let domain = SiteDomain.suggested(from: longName)

        #expect(domain.value == String(repeating: "a", count: 63) + ".localhost")
    }

    @Test
    func truncatesSuggestionsWithCounter() throws {
        let existing: Set<SiteDomain> = [
            try SiteDomain(String(repeating: "a", count: 63) + ".localhost")
        ]

        let domain = SiteDomain.suggested(from: String(repeating: "a", count: 80), existingDomains: existing)
        #expect(domain.value == String(repeating: "a", count: 61) + "-2.localhost")
    }

    private func expectInvalid(_ rawValue: String, _ expected: SiteDomainError) {
        do {
            _ = try SiteDomain(rawValue)
            Issue.record("Expected \(expected) for \(rawValue)")
        } catch let error as SiteDomainError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
