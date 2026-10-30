import Foundation
import Testing
import CodeEditLang
@testable import CodeEdit

@Suite
struct LanguageExtensionActivationTests {
    @Test
    func projectOverrideCanEnableFrameworkExtensionWithoutChangingManifest() throws {
        try withProject { root in
            let id = "test.\(UUID().uuidString)"
            let ext = makeExtension(id: id, framework: "laravel/framework")
            try writeSettings(root: root, frameworks: ["symfony/symfony"])

            let before = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(!before.isActive)
            #expect(before.reason == .declaredFrameworkMismatch(
                target: "laravel/framework",
                declared: ["symfony/symfony"]
            ))

            try writeSettings(
                root: root,
                frameworks: ["symfony/symfony"],
                overrides: [id: .enabled]
            )
            LanguageExtensionActivation.invalidate(root: root)

            let after = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(after.isActive)
            #expect(after.reason == .enabledForProject)
        }
    }

    @Test
    func projectOverrideCanDisableExtensionWithoutActivationRules() throws {
        try withProject { root in
            let id = "test.\(UUID().uuidString)"
            let ext = makeExtension(id: id)
            try writeSettings(root: root, overrides: [id: .disabled])

            let result = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(!result.isActive)
            #expect(result.reason == .disabledForProject)
            #expect(!LanguageExtensionActivation.isEnabled(ext, in: root))
        }
    }

    @Test
    func projectSettingsRoundTripOverrides() throws {
        let settings = CEWorkspaceSettingsData()
        settings.project.extensionOverrides["com.example.demo"] = .disabled

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: data)

        #expect(decoded.project.extensionOverrides["com.example.demo"] == .disabled)
        #expect(!settings.isEmpty())
    }

    @Test
    func projectFrameworkRulesReportReasons() throws {
        try withProject { root in
            let matching = makeExtension(
                id: "test.\(UUID().uuidString)",
                framework: "laravel/framework"
            )
            try writeSettings(root: root, frameworks: ["laravel/framework"])

            let result = LanguageExtensionActivation.evaluate(matching, in: root)
            #expect(result.isActive)
            #expect(result.reason == .declaredFrameworkMatch("laravel/framework"))
        }
    }

    @Test
    func frameworkActivationFileReportsMissingAndMatchingRequirements() throws {
        try withProject { root in
            let ext = makeExtension(
                id: "test.\(UUID().uuidString)",
                activation: .init(framework: .init(
                    file: "composer.json",
                    requires: ["laravel/framework": "*"]
                ))
            )

            let missing = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(!missing.isActive)
            #expect(missing.reason == .frameworkFileMissing(file: "composer.json"))

            try #"{"require":{"laravel/framework":"^11.0"}}"#
                .write(to: root.appending(path: "composer.json"), atomically: true, encoding: .utf8)

            let matched = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(matched.isActive)
            #expect(matched.reason == .frameworkFileMatch(
                file: "composer.json",
                requirement: "laravel/framework"
            ))
        }
    }

    @Test
    func literalActivationFilesAreContainedToProject() throws {
        try withProject { root in
            let ext = makeExtension(
                id: "test.\(UUID().uuidString)",
                activation: .init(files: ["artisan"])
            )

            let missing = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(!missing.isActive)
            #expect(missing.reason == .activationFilesMissing(["artisan"]))

            try "".write(to: root.appending(path: "artisan"), atomically: true, encoding: .utf8)

            let present = LanguageExtensionActivation.evaluate(ext, in: root)
            #expect(present.isActive)
            #expect(present.reason == .activationFilePresent("artisan"))
        }
    }

    private func makeExtension(
        id: String,
        framework: String? = nil,
        activation: LanguageExtensionManifest.Activation? = nil
    ) -> InstalledLanguageExtension {
        let manifest = LanguageExtensionManifest(
            id: id,
            name: "Test Extension",
            version: "1.0.0",
            framework: framework,
            activation: activation
        )
        return InstalledLanguageExtension(
            id: id,
            name: "Test Extension",
            version: "1.0.0",
            root: URL(filePath: "/tmp/\(id)", directoryHint: .isDirectory),
            manifest: manifest,
            scope: .global
        )
    }

    private func writeSettings(
        root: URL,
        frameworks: [String] = [],
        overrides: [String: ExtensionActivationOverride] = [:]
    ) throws {
        let directory = root.appending(path: ".nodalide", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var project: [String: Any] = ["frameworks": frameworks]
        if !overrides.isEmpty {
            project["extensionOverrides"] = overrides.reduce(into: [String: String]()) {
                $0[$1.key] = $1.value.rawValue
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["project": project],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appending(path: "settings.json"), options: .atomic)
    }

    private func withProject<T>(_ body: (URL) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ActivationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }
}
