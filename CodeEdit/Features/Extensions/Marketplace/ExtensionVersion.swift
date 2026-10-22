import Foundation

/// Strict semantic version used to compare catalog releases and evaluate package compatibility.
struct ExtensionVersion: Comparable, Hashable, Sendable {
    private enum PrereleaseIdentifier: Hashable, Sendable {
        case numeric(Int)
        case text(String)
    }

    let major: Int
    let minor: Int
    let patch: Int
    private let prerelease: [PrereleaseIdentifier]

    init?(_ raw: String) {
        let buildParts = raw.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard buildParts.count <= 2, let versionAndPrerelease = buildParts.first,
              buildParts.count == 1 || Self.isValidIdentifiers(
                  buildParts[1],
                  rejectsNumericLeadingZeros: false
              ) else {
            return nil
        }

        let prereleaseParts = versionAndPrerelease.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let core = prereleaseParts.first else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy(Self.isValidCoreNumber) else { return nil }
        let values = numbers.compactMap { Int($0) }
        guard values.count == 3 else { return nil }

        var identifiers: [PrereleaseIdentifier] = []
        if prereleaseParts.count == 2 {
            let rawIdentifiers = prereleaseParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !rawIdentifiers.isEmpty,
                  Self.isValidIdentifiers(prereleaseParts[1], rejectsNumericLeadingZeros: true) else {
                return nil
            }
            for identifier in rawIdentifiers {
                if identifier.allSatisfy(\.isNumber), let number = Int(identifier) {
                    identifiers.append(.numeric(number))
                } else {
                    identifiers.append(.text(String(identifier)))
                }
            }
        }

        self.major = values[0]
        self.minor = values[1]
        self.patch = values[2]
        self.prerelease = identifiers
    }

    static func < (lhs: ExtensionVersion, rhs: ExtensionVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (left, right) {
            case let (.numeric(leftNumber), .numeric(rightNumber)):
                return leftNumber < rightNumber
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case let (.text(leftText), .text(rightText)):
                return leftText < rightText
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func isValidCoreNumber(_ value: Substring) -> Bool {
        !value.isEmpty
            && value.allSatisfy(\.isNumber)
            && (value == "0" || value.first != "0")
    }

    private static func isValidIdentifiers(
        _ value: Substring,
        rejectsNumericLeadingZeros: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                return false
            }
            guard rejectsNumericLeadingZeros, identifier.allSatisfy(\.isNumber) else { return true }
            return identifier == "0" || identifier.first != "0"
        }
    }
}

/// Evaluates the catalog's package compatibility requirement against the running app version.
struct ExtensionVersionRequirement {
    private enum Constraint {
        case lessThan(ExtensionVersion)
        case lessThanOrEqual(ExtensionVersion)
        case greaterThan(ExtensionVersion)
        case greaterThanOrEqual(ExtensionVersion)
        case equal(ExtensionVersion)
    }

    private let constraints: [Constraint]

    init?(_ raw: String) {
        let tokens = raw
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return nil }

        var parsed: [Constraint] = []
        for token in tokens {
            guard let constraints = Self.constraints(from: String(token)) else { return nil }
            parsed.append(contentsOf: constraints)
        }
        constraints = parsed
    }

    func isSatisfied(by version: ExtensionVersion) -> Bool {
        constraints.allSatisfy { constraint in
            switch constraint {
            case .lessThan(let bound): version < bound
            case .lessThanOrEqual(let bound): version <= bound
            case .greaterThan(let bound): version > bound
            case .greaterThanOrEqual(let bound): version >= bound
            case .equal(let bound): version == bound
            }
        }
    }

    private static func constraints(from token: String) -> [Constraint]? {
        let operators = [">=", "<=", "^", "~", ">", "<", "="]
        let matched = operators.first { token.hasPrefix($0) }
        let versionText = matched.map { String(token.dropFirst($0.count)) } ?? token
        guard let version = ExtensionVersion(versionText) else { return nil }

        switch matched {
        case ">="?: return [.greaterThanOrEqual(version)]
        case "<="?: return [.lessThanOrEqual(version)]
        case ">"?: return [.greaterThan(version)]
        case "<"?: return [.lessThan(version)]
        case "="?: return [.equal(version)]
        case "^"?:
            return [.greaterThanOrEqual(version), .lessThan(caretUpperBound(for: version))]
        case "~"?:
            return [.greaterThanOrEqual(version), .lessThan(tildeUpperBound(for: version))]
        default:
            return [.equal(version)]
        }
    }

    private static func caretUpperBound(for version: ExtensionVersion) -> ExtensionVersion {
        if version.major > 0 {
            return ExtensionVersion("\(version.major + 1).0.0")!
        }
        if version.minor > 0 {
            return ExtensionVersion("0.\(version.minor + 1).0")!
        }
        return ExtensionVersion("0.0.\(version.patch + 1)")!
    }

    private static func tildeUpperBound(for version: ExtensionVersion) -> ExtensionVersion {
        ExtensionVersion("\(version.major).\(version.minor + 1).0")!
    }
}
