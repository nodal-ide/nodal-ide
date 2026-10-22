import Foundation

/// Immutable browse index over the currently loaded catalogs.
///
/// Built once per catalog/source/filter change so search and detail selection stay O(1) or O(entries):
/// - candidate lookup by ID is a dictionary read;
/// - search runs against pre-lowercased metadata instead of rebuilding or re-sorting the catalog.
struct ExtensionCatalogIndex {
    private(set) var candidates: [ExtensionCatalogCandidate]
    private let candidatesByID: [ExtensionCatalogCandidateID: ExtensionCatalogCandidate]
    private let searchCorpusByID: [ExtensionCatalogCandidateID: String]

    init(
        catalogs: [ExtensionSourceID: ExtensionCatalog],
        sources: [ExtensionSource],
        selectedSourceID: ExtensionSourceID?
    ) {
        let sourceByID = sources.reduce(into: [ExtensionSourceID: ExtensionSource]()) { indexed, source in
            indexed[source.id] = source
        }
        var rebuiltCandidates: [ExtensionCatalogCandidate] = []
        var rebuiltLookup: [ExtensionCatalogCandidateID: ExtensionCatalogCandidate] = [:]
        var rebuiltCorpus: [ExtensionCatalogCandidateID: String] = [:]

        for (sourceID, catalog) in catalogs {
            guard let source = sourceByID[sourceID],
                  source.isEnabled,
                  source.isTrusted,
                  selectedSourceID == nil || selectedSourceID == sourceID
            else {
                continue
            }

            for (extensionID, entry) in catalog.extensions {
                guard let package = entry.versions[entry.latest] else {
                    continue
                }

                let candidate = ExtensionCatalogCandidate(
                    sourceID: sourceID,
                    extensionID: extensionID,
                    version: entry.latest,
                    entry: entry,
                    package: package
                )

                rebuiltCandidates.append(candidate)
                rebuiltLookup[candidate.id] = candidate
                rebuiltCorpus[candidate.id] = Self.searchCorpus(for: candidate)
            }
        }

        rebuiltCandidates.sort(by: Self.areCandidatesOrdered)
        candidates = rebuiltCandidates
        candidatesByID = rebuiltLookup
        searchCorpusByID = rebuiltCorpus
    }

    var count: Int { candidates.count }

    func candidate(for id: ExtensionCatalogCandidateID) -> ExtensionCatalogCandidate? {
        candidatesByID[id]
    }

    func candidates(matching rawQuery: String) -> [ExtensionCatalogCandidate] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter { searchCorpusByID[$0.id]?.contains(query) == true }
    }

    private static func searchCorpus(for candidate: ExtensionCatalogCandidate) -> String {
        [
            candidate.entry.name,
            candidate.entry.description,
            candidate.entry.publisher,
            candidate.extensionID
        ]
        .joined(separator: "\n")
        .lowercased()
    }

    private static func areCandidatesOrdered(
        _ lhs: ExtensionCatalogCandidate,
        _ rhs: ExtensionCatalogCandidate
    ) -> Bool {
        let nameOrder = lhs.entry.name.localizedStandardCompare(rhs.entry.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        let publisherOrder = lhs.entry.publisher.localizedStandardCompare(rhs.entry.publisher)
        if publisherOrder != .orderedSame {
            return publisherOrder == .orderedAscending
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID.rawValue.uuidString < rhs.sourceID.rawValue.uuidString
        }
        return lhs.extensionID < rhs.extensionID
    }
}
