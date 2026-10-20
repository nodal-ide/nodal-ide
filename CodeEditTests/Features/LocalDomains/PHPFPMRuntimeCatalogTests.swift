import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct PHPFPMRuntimeCatalogTests {
    @Test
    func statusesAreKeyedByRuntimeIdentity() async {
        let available = runtime(version: "8.4.12")
        let missing = runtime(version: "8.3.6")
        let detector = FakePHPFPMDetector()
        detector.statuses = [
            available.id: .available(
                PHPFPMInstallation(executableURL: URL(filePath: "/opt/php/sbin/php-fpm"), version: "8.4.12")
            ),
            missing.id: .missing
        ]
        let catalog = PHPFPMRuntimeCatalog(detector: detector)

        let statuses = await catalog.statuses(for: [available, missing])

        #expect(statuses[available.id]?.isAvailable == true)
        #expect(statuses[missing.id] == .missing)
        #expect(detector.probedRuntimes == [available, missing])
    }

    @Test
    func usableRuntimesKeepOnlyAvailableVersionsNewestFirst() async {
        let newest = runtime(version: "8.4.12")
        let older = runtime(version: "8.2.7")
        let withoutFPM = runtime(version: "8.3.6")
        let catalog = PHPFPMRuntimeCatalog(detector: detector(
            available: [newest, older],
            missing: [withoutFPM]
        ))

        let usable = await catalog.usableRuntimes(from: [older, withoutFPM, newest])

        #expect(usable.map(\.version) == ["8.4.12", "8.2.7"])
        #expect(usable.first?.installation.version == "8.4.12")
        #expect(usable.first?.runtime == newest)
    }

    @Test
    func versionMismatchIsNotUsable() async {
        let runtime = runtime(version: "8.4.12")
        let detector = FakePHPFPMDetector()
        detector.defaultStatus = .versionMismatch(expected: "8.4.12", found: "8.3.6")
        let catalog = PHPFPMRuntimeCatalog(detector: detector)

        #expect(await catalog.usableRuntimes(from: [runtime]).isEmpty)
    }

    @Test
    func resolvePrefersTheRequestedVersion() async {
        let newest = runtime(version: "8.4.12")
        let pinned = runtime(version: "8.2.7")
        let catalog = PHPFPMRuntimeCatalog(detector: detector(available: [newest, pinned]))

        #expect(await catalog.resolve(version: "8.2.7", from: [newest, pinned])?.version == "8.2.7")
    }

    @Test
    func resolveFallsBackToTheNewestUsableVersionOnlyWhenUnpinned() async throws {
        let newest = runtime(version: "8.4.12")
        let older = runtime(version: "8.2.7")
        let catalog = PHPFPMRuntimeCatalog(detector: detector(available: [newest, older]))

        let missingVersion = await catalog.resolve(version: "8.1.0", from: [older, newest])
        let noVersion = await catalog.resolve(version: nil, from: [older, newest])

        #expect(missingVersion == nil)
        #expect(noVersion?.version == "8.4.12")
        #expect(await catalog.resolve(version: "8.1.0", from: []) == nil)
    }

    @Test
    func statusDisplayExplainsAvailability() {
        let installation = PHPFPMInstallation(executableURL: URL(filePath: "/opt/php/sbin/php-fpm"), version: "8.4.12")

        #expect(PHPFPMStatus.available(installation).badgeText == "FPM")
        #expect(PHPFPMStatus.available(installation).detail == "PHP-FPM 8.4.12 available")
        #expect(PHPFPMStatus.missing.badgeText == "No FPM")
        #expect(PHPFPMStatus.missing.detail == "No php-fpm found for this PHP version")
        #expect(PHPFPMStatus.versionMismatch(expected: "8.4.12", found: "8.3.6").badgeText == "FPM 8.3.6")
        #expect(
            PHPFPMStatus.versionMismatch(expected: "8.4.12", found: "8.3.6").detail
                == "php-fpm 8.3.6 does not match PHP 8.4.12"
        )
        #expect(PHPFPMStatus.unusable(URL(filePath: "/tmp/fpm")).badgeText == "No FPM")
        #expect(PHPFPMStatus.unusable(URL(filePath: "/tmp/fpm")).detail == "fpm does not report a PHP version")
    }

    // MARK: - Helpers

    private func runtime(version: String) -> InstalledRuntime {
        InstalledRuntime(
            kind: .php,
            version: version,
            source: .brew,
            executableDirectory: URL(filePath: "/opt/php/\(version)/bin", directoryHint: .isDirectory)
        )
    }

    private func detector(available: [InstalledRuntime], missing: [InstalledRuntime] = []) -> FakePHPFPMDetector {
        let detector = FakePHPFPMDetector()
        for runtime in available {
            detector.statuses[runtime.id] = .available(
                PHPFPMInstallation(
                    executableURL: runtime.executable(relativePath: "sbin/php-fpm"),
                    version: runtime.version
                )
            )
        }
        for runtime in missing {
            detector.statuses[runtime.id] = .missing
        }
        return detector
    }
}
