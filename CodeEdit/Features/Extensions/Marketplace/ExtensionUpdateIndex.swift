import Foundation

/// A compatible update for an installed marketplace extension from its recorded source.
struct ExtensionUpdate: Identifiable, Equatable {
    let installed: InstalledLanguageExtension
    let candidate: ExtensionCatalogCandidate
    let source: ExtensionSource

    var id: String { installed.id }
    var installedVersion: String { installed.version ?? "Unknown" }
    var availableVersion: String { candidate.version }
}

/// A marketplace-installed extension that is already at the latest catalog version.
struct ExtensionUpToDate: Equatable {
    let installed: InstalledLanguageExtension
    let sourceName: String
}

enum ExtensionUpdateIssueReason: Equatable {
    case sourceMissing
    case sourceDisabled
    case sourceUntrusted
    case catalogUnavailable
    case notInCatalog
    case incompatible(requirement: String)
    case invalidRequirement(String)
    case invalidVersion(String)
    case unknownHostVersion
}

/// An installed marketplace extension whose update status cannot be determined.
struct ExtensionUpdateIssue: Identifiable, Equatable {
    let installed: InstalledLanguageExtension
    let sourceName: String
    let reason: ExtensionUpdateIssueReason

    var id: String { installed.id }
}

/// Pure update view over installed provenance and the currently loaded catalogs.
///
/// Updates are only offered from the source recorded in provenance. Another source may contain a
/// different candidate, but that is a deliberate source switch handled by Discover, never an
/// automatic update. Catalog state (fresh/stale/offline) is presentation-only: cached catalogs still
/// produce updates, while the UI explains that data may be stale.
struct ExtensionUpdateIndex {
    let availableUpdates: [ExtensionUpdate]
    let upToDate: [ExtensionUpToDate]
    let issues: [ExtensionUpdateIssue]

    var trackedCount: Int {
        availableUpdates.count + upToDate.count + issues.count
    }

    init(
        installed: [InstalledLanguageExtension],
        catalogs: [ExtensionSourceID: ExtensionCatalog],
        sources: [ExtensionSource],
        appVersion: String?
    ) {
        let sourceByID = sources.reduce(into: [ExtensionSourceID: ExtensionSource]()) { indexed, source in
            indexed[source.id] = source
        }
        let hostVersion = appVersion.flatMap(ExtensionVersion.init)
        var updates: [ExtensionUpdate] = []
        var current: [ExtensionUpToDate] = []
        var problems: [ExtensionUpdateIssue] = []

        for ext in installed {
            guard let provenance = ext.provenance else { continue }
            switch Self.evaluate(
                ext,
                provenance: provenance,
                sourceByID: sourceByID,
                catalogs: catalogs,
                hostVersion: hostVersion
            ) {
            case .update(let update):
                updates.append(update)
            case .upToDate(let currentExtension):
                current.append(currentExtension)
            case .issue(let issue):
                problems.append(issue)
            }
        }

        availableUpdates = updates.sorted(by: Self.areOrdered)
        upToDate = current.sorted { $0.installed.name.localizedStandardCompare($1.installed.name) == .orderedAscending }
        issues = problems.sorted { $0.installed.name.localizedStandardCompare($1.installed.name) == .orderedAscending }
    }

    private enum Evaluation {
        case update(ExtensionUpdate)
        case upToDate(ExtensionUpToDate)
        case issue(ExtensionUpdateIssue)
    }

    private struct ResolvedPackage {
        let installed: InstalledLanguageExtension
        let source: ExtensionSource
        let entry: ExtensionCatalogEntry
        let package: ExtensionCatalogVersion
    }

    private static func evaluate(
        _ ext: InstalledLanguageExtension,
        provenance: ExtensionProvenance,
        sourceByID: [ExtensionSourceID: ExtensionSource],
        catalogs: [ExtensionSourceID: ExtensionCatalog],
        hostVersion: ExtensionVersion?
    ) -> Evaluation {
        guard let source = sourceByID[provenance.sourceID] else {
            return .issue(.init(installed: ext, sourceName: provenance.sourceName, reason: .sourceMissing))
        }
        guard source.isEnabled else {
            return .issue(.init(installed: ext, sourceName: source.name, reason: .sourceDisabled))
        }
        guard source.isTrusted else {
            return .issue(.init(installed: ext, sourceName: source.name, reason: .sourceUntrusted))
        }
        guard let catalog = catalogs[source.id] else {
            return .issue(.init(installed: ext, sourceName: source.name, reason: .catalogUnavailable))
        }
        guard let entry = catalog.extensions[ext.id],
              let package = entry.versions[entry.latest] else {
            return .issue(.init(installed: ext, sourceName: source.name, reason: .notInCatalog))
        }
        return evaluate(
            ResolvedPackage(installed: ext, source: source, entry: entry, package: package),
            hostVersion: hostVersion
        )
    }

    private static func evaluate(
        _ resolved: ResolvedPackage,
        hostVersion: ExtensionVersion?
    ) -> Evaluation {
        let ext = resolved.installed
        let sourceName = resolved.source.name
        guard let installedVersion = ext.version.flatMap(ExtensionVersion.init) else {
            return .issue(.init(
                installed: ext,
                sourceName: sourceName,
                reason: .invalidVersion(ext.version ?? "missing")
            ))
        }
        guard let availableVersion = ExtensionVersion(resolved.entry.latest) else {
            return .issue(.init(
                installed: ext,
                sourceName: sourceName,
                reason: .invalidVersion(resolved.entry.latest)
            ))
        }
        guard availableVersion > installedVersion else {
            return .upToDate(.init(installed: ext, sourceName: sourceName))
        }
        if let requirementText = resolved.package.nodal {
            guard let requirement = ExtensionVersionRequirement(requirementText) else {
                return .issue(.init(
                    installed: ext,
                    sourceName: sourceName,
                    reason: .invalidRequirement(requirementText)
                ))
            }
            guard let hostVersion else {
                return .issue(.init(installed: ext, sourceName: sourceName, reason: .unknownHostVersion))
            }
            guard requirement.isSatisfied(by: hostVersion) else {
                return .issue(.init(
                    installed: ext,
                    sourceName: sourceName,
                    reason: .incompatible(requirement: requirementText)
                ))
            }
        }
        return .update(.init(
            installed: ext,
            candidate: ExtensionCatalogCandidate(
                sourceID: resolved.source.id,
                extensionID: ext.id,
                version: resolved.entry.latest,
                entry: resolved.entry,
                package: resolved.package
            ),
            source: resolved.source
        ))
    }

    private static func areOrdered(_ lhs: ExtensionUpdate, _ rhs: ExtensionUpdate) -> Bool {
        let nameOrder = lhs.installed.name.localizedStandardCompare(rhs.installed.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.source.name.localizedStandardCompare(rhs.source.name) == .orderedAscending
    }
}
