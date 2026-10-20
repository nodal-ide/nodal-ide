import Foundation
import Testing
@testable import CodeEdit

struct RunConfigurationTests {
    @Test
    func siteKindHasMetadata() {
        #expect(RunConfiguration.Kind.site.title == "Site")
        #expect(RunConfiguration.Kind.site.systemImage == "globe")
        #expect(RunConfiguration.Kind.allCases.contains(.site))
    }

    @Test
    func siteConfigurationDoesNotRequireCommand() {
        var configuration = RunConfiguration()
        configuration.name = "Site"
        configuration.kind = .site

        #expect(!configuration.isInvalid)
    }

    @Test
    func siteConfigurationRequiresName() {
        var configuration = RunConfiguration()
        configuration.kind = .site

        #expect(configuration.isInvalid)
    }

    @Test
    func otherKindsStillRequireCommands() {
        var run = RunConfiguration()
        run.name = "Run"
        #expect(run.isInvalid)

        run.command = "php forge.php serve"
        #expect(!run.isInvalid)

        var debug = RunConfiguration()
        debug.name = "Debug"
        debug.kind = .debug
        #expect(debug.isInvalid)

        debug.program = "vendor/bin/phpunit"
        #expect(!debug.isInvalid)
    }

    @Test
    func siteKindSurvivesCodableRoundTrip() throws {
        var configuration = RunConfiguration()
        configuration.name = "Site"
        configuration.kind = .site
        configuration.command = ""

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(RunConfiguration.self, from: data)

        #expect(decoded.kind == .site)
        #expect(decoded.name == "Site")
        #expect(!decoded.isInvalid)
    }
}
