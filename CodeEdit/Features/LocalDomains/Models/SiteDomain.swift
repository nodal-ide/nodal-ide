import Foundation

struct SiteDomain: Hashable, Sendable, CustomStringConvertible {
    static let suffix = ".localhost"

    private static let maxLabelLength = 63
    private static let maxHostLength = 253

    let value: String

    init(_ rawValue: String) throws {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }

        guard !normalized.isEmpty else {
            throw SiteDomainError.empty
        }

        if !normalized.hasSuffix(Self.suffix) {
            guard !normalized.contains(".") else {
                throw SiteDomainError.unsupportedSuffix
            }
            normalized += Self.suffix
        }

        try Self.validate(normalized)
        self.value = normalized
    }

    var description: String { value }

    static func suggested(from projectName: String, existingDomains: Set<SiteDomain> = []) -> SiteDomain {
        let base = sanitizedLabel(projectName)
        var counter = 1

        while true {
            let suffix = counter == 1 ? "" : "-\(counter)"
            let candidate = makeLabel(base: base, suffix: suffix) + Self.suffix
            let domain = SiteDomain(uncheckedValue: candidate)

            if !existingDomains.contains(domain) {
                return domain
            }

            counter += 1
        }
    }

    private init(uncheckedValue: String) {
        self.value = uncheckedValue
    }

    private static func validate(_ host: String) throws {
        guard host.count <= maxHostLength else {
            throw SiteDomainError.domainTooLong
        }

        let subdomain = host.dropLast(Self.suffix.count)

        guard !subdomain.isEmpty else {
            throw SiteDomainError.missingLabel
        }

        let labels = subdomain.split(separator: ".", omittingEmptySubsequences: false)

        for label in labels {
            try validate(label: String(label))
        }
    }

    private static func validate(label: String) throws {
        guard !label.isEmpty else {
            throw SiteDomainError.emptyLabel
        }

        guard label.count <= maxLabelLength else {
            throw SiteDomainError.labelTooLong
        }

        guard !label.hasPrefix("-"), !label.hasSuffix("-") else {
            throw SiteDomainError.invalidLabel
        }

        guard label.unicodeScalars.allSatisfy(isAllowed) else {
            throw SiteDomainError.invalidCharacters
        }
    }

    private static func sanitizedLabel(_ name: String) -> String {
        let folded = name.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        var result = ""
        var lastWasHyphen = false

        for scalar in folded.lowercased().unicodeScalars {
            if isAllowed(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasHyphen = scalar.value == 45
            } else if !lastWasHyphen {
                result.append("-")
                lastWasHyphen = true
            }
        }

        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if result.isEmpty {
            result = "project"
        }

        return String(result.prefix(maxLabelLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func makeLabel(base: String, suffix: String) -> String {
        let available = max(1, maxLabelLength - suffix.count)
        let truncated = String(base.prefix(available))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return (truncated.isEmpty ? "project" : truncated) + suffix
    }

    private static func isAllowed(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 97 && scalar.value <= 122)
            || (scalar.value >= 48 && scalar.value <= 57)
            || scalar.value == 45
    }
}

enum SiteDomainError: Error, Equatable, LocalizedError {
    case empty
    case unsupportedSuffix
    case missingLabel
    case emptyLabel
    case labelTooLong
    case invalidLabel
    case invalidCharacters
    case domainTooLong

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a local domain."
        case .unsupportedSuffix:
            return "Local domains must end in .localhost."
        case .missingLabel:
            return "Enter a name before .localhost."
        case .emptyLabel:
            return "The domain contains an empty label."
        case .labelTooLong:
            return "Each domain label must be 63 characters or fewer."
        case .invalidLabel:
            return "Domain labels cannot start or end with a hyphen."
        case .invalidCharacters:
            return "Use only lowercase letters, numbers, and hyphens."
        case .domainTooLong:
            return "The domain is too long."
        }
    }
}
