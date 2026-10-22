//
//  ExtensionRegistryCatalogDocument.swift
//  CodeEdit
//
//  Reads and edits extensions.json while preserving fields this editor does not understand.
//

import Foundation

struct ExtensionRegistryCatalogDocument {
    static let catalogFileName = "extensions.json"

    private var root: [String: Any]
    private var extensions: [String: Any]

    init(data: Data?) throws {
        guard let data, !data.isEmpty else {
            root = ["schemaVersion": 1, "extensions": [String: Any]()]
            extensions = [:]
            return
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExtensionRegistryError.invalidCatalog(error.localizedDescription)
        }
        guard let root = object as? [String: Any],
              let schemaVersion = root["schemaVersion"] as? Int,
              schemaVersion == 1,
              let extensions = root["extensions"] as? [String: Any] else {
            throw ExtensionRegistryError.invalidCatalog(
                "Expected schemaVersion 1 and an extensions object."
            )
        }
        self.root = root
        self.extensions = extensions
        try validateObject()
    }

    var extensionCount: Int {
        extensions.count
    }

    func latestVersion(for extensionID: String) -> String? {
        (extensions[extensionID] as? [String: Any])?["latest"] as? String
    }

    func contains(extensionID: String, version: String) -> Bool {
        integrity(extensionID: extensionID, version: version) != nil
    }

    func integrity(extensionID: String, version: String) -> String? {
        guard let entry = extensions[extensionID] as? [String: Any],
              let versions = entry["versions"] as? [String: Any],
              let package = versions[version] as? [String: Any] else {
            return nil
        }
        return package["integrity"] as? String
    }

    /// Returns the complete catalog data after adding one release, without modifying this document.
    func addingRelease(
        _ release: ExtensionRegistryRelease,
        packageURL: String,
        integrity: String,
        publishedAt: Date = .now
    ) throws -> (data: Data, latestAdvanced: Bool) {
        let extensionID = release.manifest.id
        let version = release.manifest.version
        guard Self.isSemVer(version) else {
            throw ExtensionRegistryError.invalidManifest("`version` must be Semantic Versioning (for example 1.2.3).")
        }

        var entry = extensions[extensionID] as? [String: Any] ?? [:]
        var versions = entry["versions"] as? [String: Any] ?? [:]
        guard versions[version] == nil else {
            throw ExtensionRegistryError.duplicateVersion(extensionID: extensionID, version: version)
        }

        let formatter = ISO8601DateFormatter()
        let package: [String: Any] = [
            "url": packageURL,
            "integrity": integrity,
            "publishedAt": formatter.string(from: publishedAt)
        ]
        versions[version] = package

        let existingLatest = entry["latest"] as? String
        let latestAdvanced: Bool
        let latest: String
        if let existingLatest, Self.isSemVer(existingLatest), !Self.isGreater(version, than: existingLatest) {
            latest = existingLatest
            latestAdvanced = false
        } else {
            latest = version
            latestAdvanced = true
        }

        entry["name"] = release.catalogName
        entry["description"] = release.catalogDescription
        entry["publisher"] = release.catalogPublisher
        entry["latest"] = latest
        entry["versions"] = versions
        entry["url"] = release.catalogHomepage?.absoluteString ?? NSNull()

        var updatedRoot = root
        var updatedExtensions = extensions
        updatedExtensions[extensionID] = entry
        updatedRoot["extensions"] = updatedExtensions

        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: updatedRoot,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw ExtensionRegistryError.invalidCatalog(error.localizedDescription)
        }

        // Validate the exact bytes that will be committed, not just the mutation in memory.
        try Self.validateCatalogData(data + Data("\n".utf8))
        return (data + Data("\n".utf8), latestAdvanced)
    }

    static func emptyCatalogData() -> Data {
        Data("{\n  \"schemaVersion\" : 1,\n  \"extensions\" : {\n\n  }\n}\n".utf8)
    }

    static func validateCatalogData(_ data: Data) throws {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let catalog = try decoder.decode(ExtensionCatalog.self, from: data)
            try ExtensionCatalogValidator.validate(catalog)
        } catch {
            throw ExtensionRegistryError.invalidCatalog(error.localizedDescription)
        }
    }

    private func validateObject() throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try Self.validateCatalogData(data)
    }

    // MARK: - SemVer

    static func isSemVer(_ value: String) -> Bool {
        parse(value) != nil
    }

    static func isGreater(_ lhs: String, than rhs: String) -> Bool {
        guard let left = parse(lhs), let right = parse(rhs) else { return false }
        if left.major != right.major { return left.major > right.major }
        if left.minor != right.minor { return left.minor > right.minor }
        if left.patch != right.patch { return left.patch > right.patch }
        return isPrereleaseGreater(left.prerelease, than: right.prerelease)
    }

    private static func isPrereleaseGreater(_ left: [String]?, than right: [String]?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (leftIdentifiers?, rightIdentifiers?):
            for (leftIdentifier, rightIdentifier) in zip(leftIdentifiers, rightIdentifiers)
            where leftIdentifier != rightIdentifier {
                return isIdentifierGreater(leftIdentifier, than: rightIdentifier)
            }
            return leftIdentifiers.count > rightIdentifiers.count
        }
    }

    private static func isIdentifierGreater(_ left: String, than right: String) -> Bool {
        switch (Int(left), Int(right)) {
        case let (leftNumber?, rightNumber?):
            return leftNumber > rightNumber
        case (_?, nil):
            return false
        case (nil, _?):
            return true
        default:
            return left > right
        }
    }

    private struct SemanticVersion {
        let major: Int
        let minor: Int
        let patch: Int
        let prerelease: [String]?
    }

    private static func parse(_ value: String) -> SemanticVersion? {
        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2, let versionAndPrerelease = buildParts.first else { return nil }
        if buildParts.count == 2,
           !validIdentifiers(buildParts[1], numericIdentifiersCannotHaveLeadingZero: false) {
            return nil
        }

        let prereleaseParts = versionAndPrerelease.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let core = prereleaseParts.first else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = validCoreNumber(numbers[0]),
              let minor = validCoreNumber(numbers[1]),
              let patch = validCoreNumber(numbers[2]) else {
            return nil
        }

        var prerelease: [String]?
        if prereleaseParts.count == 2 {
            guard validIdentifiers(prereleaseParts[1], numericIdentifiersCannotHaveLeadingZero: true) else {
                return nil
            }
            prerelease = prereleaseParts[1].split(separator: ".").map(String.init)
        }
        return SemanticVersion(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    private static func validCoreNumber(_ value: Substring) -> Int? {
        guard !value.isEmpty,
              value.utf8.allSatisfy({ (48...57).contains($0) }),
              value == "0" || value.first != "0" else {
            return nil
        }
        return Int(value)
    }

    private static func validIdentifiers(
        _ value: Substring,
        numericIdentifiersCannotHaveLeadingZero: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == 45 }) else {
                return false
            }
            guard numericIdentifiersCannotHaveLeadingZero,
                  identifier.utf8.allSatisfy({ (48...57).contains($0) }) else {
                return true
            }
            return identifier == "0" || identifier.first != "0"
        }
    }
}

extension ExtensionCatalogValidator {
    static func isRegistryExtensionID(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            guard let first = segment.utf8.first, first.isASCIIAlpha,
                  let last = segment.utf8.last, last.isASCIIAlphaNumeric else {
                return false
            }
            return segment.utf8.dropFirst().allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            }
        }
    }
}

private extension UInt8 {
    var isASCIIAlpha: Bool { (65...90).contains(self) || (97...122).contains(self) }
    var isASCIIAlphaNumeric: Bool { isASCIIAlpha || (48...57).contains(self) }
}
