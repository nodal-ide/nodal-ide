import Foundation

struct ExtensionSourceID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ExtensionSource: Codable, Hashable, Identifiable, Sendable {
    let id: ExtensionSourceID
    var name: String
    var providerID: ExtensionSourceProviderID
    var location: URL
    /// Optional branch, tag, or commit for Git repository sources.
    var revision: String?
    var isEnabled: Bool
    var isTrusted: Bool
    var refreshInterval: TimeInterval?
    var credentialReference: String?
    var createdAt: Date
    var trustChangedAt: Date?

    init(
        id: ExtensionSourceID = .init(),
        name: String,
        providerID: ExtensionSourceProviderID,
        location: URL,
        revision: String? = nil,
        isEnabled: Bool = true,
        isTrusted: Bool = false,
        refreshInterval: TimeInterval? = nil,
        credentialReference: String? = nil,
        createdAt: Date = .now,
        trustChangedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.providerID = providerID
        self.location = location
        self.revision = revision
        self.isEnabled = isEnabled
        self.isTrusted = isTrusted
        self.refreshInterval = refreshInterval
        self.credentialReference = credentialReference
        self.createdAt = createdAt
        self.trustChangedAt = trustChangedAt
    }
}

struct ExtensionSourceCollection: Sendable {
    let sources: [ExtensionSource]

    init(sources: [ExtensionSource]) throws {
        var identifiers = Set<ExtensionSourceID>()
        var locations = Set<SourceLocationKey>()

        for source in sources {
            guard identifiers.insert(source.id).inserted else {
                throw ExtensionSourceCollectionError.duplicateSourceID(source.id)
            }
            guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source.name.utf8.count <= 128,
                  !source.providerID.rawValue.isEmpty,
                  source.refreshInterval.map({ $0.isFinite && $0 >= 60 && $0 <= 604_800 }) ?? true else {
                throw ExtensionSourceCollectionError.invalidSourceConfiguration(source.id)
            }
            guard let key = SourceLocationKey(source: source) else {
                throw ExtensionSourceCollectionError.invalidSourceLocation(source.id)
            }
            guard locations.insert(key).inserted else {
                throw ExtensionSourceCollectionError.duplicateSourceLocation
            }
        }
        self.sources = sources
    }
}

private struct SourceLocationKey: Hashable {
    let providerID: ExtensionSourceProviderID
    let location: String
    let revision: String?

    init?(source: ExtensionSource) {
        guard var components = URLComponents(url: source.location, resolvingAgainstBaseURL: false),
              components.password == nil,
              components.query == nil,
              components.fragment == nil else { return nil }

        switch source.providerID {
        case .httpsStaticIndex:
            guard components.scheme?.lowercased() == "https",
                  components.host != nil,
                  components.user == nil else { return nil }
        case .gitRepository:
            guard GitRepositoryLocation.isValid(source.location),
                  GitRepositoryLocation.isValidRevision(source.revision) else { return nil }
        default:
            guard components.user == nil else { return nil }
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.scheme == "https" && components.port == 443
            || components.scheme == "http" && components.port == 80 {
            components.port = nil
        }
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let normalizedURL = components.url else { return nil }
        self.providerID = source.providerID
        self.location = normalizedURL.absoluteString
        self.revision = source.providerID == .gitRepository
            ? GitRepositoryLocation.normalizedRevision(source.revision)
            : nil
    }
}

enum ExtensionSourceCollectionError: Error, Equatable {
    case duplicateSourceID(ExtensionSourceID)
    case invalidSourceConfiguration(ExtensionSourceID)
    case invalidSourceLocation(ExtensionSourceID)
    case duplicateSourceLocation
}

struct ExtensionSourceProviderID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    static let httpsStaticIndex: Self = "https-static-index"
    static let gitRepository: Self = "git-repository"
}

struct ExtensionCatalog: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let extensions: [String: ExtensionCatalogEntry]
}

struct ExtensionCatalogEntry: Codable, Hashable, Sendable {
    let name: String
    let description: String
    let publisher: String
    let url: URL?
    let latest: String
    let versions: [String: ExtensionCatalogVersion]
}

struct ExtensionCatalogVersion: Codable, Hashable, Sendable {
    let url: URL
    let integrity: String
    let publishedAt: Date?
    let nodal: String?
}

struct ExtensionCatalogCandidateID: Hashable, Sendable {
    let sourceID: ExtensionSourceID
    let extensionID: String
    let version: String
}

struct ExtensionCatalogCandidate: Hashable, Sendable, Identifiable {
    let sourceID: ExtensionSourceID
    let extensionID: String
    let version: String
    let entry: ExtensionCatalogEntry
    let package: ExtensionCatalogVersion

    var id: ExtensionCatalogCandidateID {
        ExtensionCatalogCandidateID(sourceID: sourceID, extensionID: extensionID, version: version)
    }
}

enum ExtensionCatalogValidationError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidExtensionID(String)
    case invalidMetadata(String)
    case invalidVersion(String)
    case missingLatestVersion(String)
    case invalidIntegrity(extensionID: String, version: String)
    case invalidHomepageURL(String)
    case invalidPackageURL(extensionID: String, version: String)
}

enum ExtensionCatalogValidator {
    static func validate(_ catalog: ExtensionCatalog) throws {
        guard catalog.schemaVersion == 1 else {
            throw ExtensionCatalogValidationError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        for (extensionID, entry) in catalog.extensions {
            try validate(entry, extensionID: extensionID)
        }
    }

    private static func validate(
        _ entry: ExtensionCatalogEntry,
        extensionID: String
    ) throws {
        guard isReverseDNSIdentifier(extensionID) else {
            throw ExtensionCatalogValidationError.invalidExtensionID(extensionID)
        }
        try validateMetadata(entry, extensionID: extensionID)
        guard isSemVer(entry.latest) else {
            throw ExtensionCatalogValidationError.invalidVersion(entry.latest)
        }
        guard entry.versions[entry.latest] != nil else {
            throw ExtensionCatalogValidationError.missingLatestVersion(extensionID)
        }
        for (version, package) in entry.versions {
            try validate(version: version, package: package, extensionID: extensionID)
        }
    }

    private static func validateMetadata(
        _ entry: ExtensionCatalogEntry,
        extensionID: String
    ) throws {
        guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entry.name.utf8.count <= 128,
              !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entry.description.utf8.count <= 4_096,
              !entry.publisher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entry.publisher.utf8.count <= 128 else {
            throw ExtensionCatalogValidationError.invalidMetadata(extensionID)
        }
        if let homepage = entry.url {
            guard homepage.scheme?.lowercased() == "https",
                  homepage.host != nil,
                  homepage.user == nil,
                  homepage.password == nil else {
                throw ExtensionCatalogValidationError.invalidHomepageURL(extensionID)
            }
        }
    }

    private static func validate(
        version: String,
        package: ExtensionCatalogVersion,
        extensionID: String
    ) throws {
        guard isSemVer(version) else {
            throw ExtensionCatalogValidationError.invalidVersion(version)
        }
        let hasSHA256Digest = package.integrity.utf8.count == 64
            && package.integrity.utf8.allSatisfy(Self.isLowercaseHexDigit)
        guard hasSHA256Digest else {
            throw ExtensionCatalogValidationError.invalidIntegrity(
                extensionID: extensionID,
                version: version
            )
        }
        let scheme = package.url.scheme?.lowercased()
        guard scheme == nil || scheme == "https",
              scheme != nil || package.url.host == nil,
              package.url.user == nil,
              package.url.password == nil else {
            throw ExtensionCatalogValidationError.invalidPackageURL(
                extensionID: extensionID,
                version: version
            )
        }
    }

    private static func isSemVer(_ value: String) -> Bool {
        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2, let versionAndPrerelease = buildParts.first else { return false }
        if buildParts.count == 2, !areValidIdentifiers(buildParts[1], enforceNumericLeadingZeroRule: false) {
            return false
        }

        let prereleaseParts = versionAndPrerelease.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let core = prereleaseParts.first else { return false }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy(isValidCoreNumber) else { return false }
        guard prereleaseParts.count == 2 else { return true }
        return areValidIdentifiers(prereleaseParts[1], enforceNumericLeadingZeroRule: true)
    }

    private static func isValidCoreNumber(_ value: Substring) -> Bool {
        !value.isEmpty
            && value.utf8.allSatisfy { (48...57).contains($0) }
            && (value == "0" || value.first != "0")
    }

    private static func areValidIdentifiers(
        _ value: Substring,
        enforceNumericLeadingZeroRule: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == 45 }) else { return false }
            guard enforceNumericLeadingZeroRule,
                  identifier.utf8.allSatisfy({ (48...57).contains($0) }) else { return true }
            return identifier == "0" || identifier.first != "0"
        }
    }

    private static func isLowercaseHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (97...102).contains(byte)
    }

    private static func isReverseDNSIdentifier(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            guard let first = segment.utf8.first, first.isASCIIAlpha else { return false }
            guard let last = segment.utf8.last, last.isASCIIAlphaNumeric else { return false }
            return segment.utf8.dropFirst().allSatisfy { $0.isASCIIAlphaNumeric || $0 == 45 }
        }
    }
}

private extension UInt8 {
    var isASCIIAlpha: Bool { (65...90).contains(self) || (97...122).contains(self) }
    var isASCIIAlphaNumeric: Bool { isASCIIAlpha || (48...57).contains(self) }
}
