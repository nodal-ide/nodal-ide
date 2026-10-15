//
//  RuntimeCatalog.swift
//  CodeEdit
//
//  Fetches and caches the list of versions available to install per runtime.
//

import Foundation

enum RuntimeCatalog {
    /// How long a cached catalog is considered fresh.
    private static let ttl: TimeInterval = 6 * 3600

    /// Returns the catalog for a runtime, from cache when fresh, otherwise fetched (and cached).
    static func versions(for kind: RuntimeKind) async -> [RuntimeVersion] {
        if let cache = load(kind), Date().timeIntervalSince(cache.fetchedAt) < ttl, !cache.versions.isEmpty {
            return cache.versions
        }

        let fetched: [RuntimeVersion]
        switch kind {
        case .node: fetched = await fetchNode()
        case .php: fetched = await fetchPHP()
        case .typescript: fetched = []
        }

        guard !fetched.isEmpty else {
            return load(kind)?.versions ?? []
        }
        save(kind, fetched)
        return fetched
    }

    // MARK: - Sources

    private static func fetchNode() async -> [RuntimeVersion] {
        guard let url = URL(string: "https://nodejs.org/dist/index.json"),
              let data = try? await URLSession.shared.data(from: url).0,
              let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return releases.compactMap { release in
            guard let rawVersion = release["version"] as? String else { return nil }
            let version = rawVersion.hasPrefix("v") ? String(rawVersion.dropFirst()) : rawVersion
            let lts = release["lts"] as? String
            let date = (release["date"] as? String).flatMap(formatter.date(from:))
            return RuntimeVersion(version: version, isLTS: lts != nil, releaseDate: date)
        }
    }

    private static func fetchPHP() async -> [RuntimeVersion] {
        // Homebrew keeps one formula per PHP minor (`php@8.3`, …) plus the default `php`.
        let formulae = ["php", "php@8.4", "php@8.3", "php@8.2", "php@8.1", "php@8.0"]
        var versions: [RuntimeVersion] = []

        for formula in formulae {
            guard let url = URL(string: "https://formulae.brew.sh/api/formula/\(formula).json"),
                  let data = try? await URLSession.shared.data(from: url).0,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versionsAny = object["versions"] as? [String: Any],
                  let stable = versionsAny["stable"] as? String else {
                continue
            }
            versions.append(
                RuntimeVersion(version: stable, isLTS: formula == "php", installIdentifier: formula)
            )
        }
        return deduplicated(versions)
    }

    private static func deduplicated(_ versions: [RuntimeVersion]) -> [RuntimeVersion] {
        var seen = Set<String>()
        return versions.filter { seen.insert($0.version).inserted }
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let fetchedAt: Date
        let versions: [RuntimeVersion]
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codeedit")
            .appending(path: "cache")
            .appending(path: "runtimes")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func cacheURL(_ kind: RuntimeKind) -> URL {
        cacheDirectory.appending(path: "\(kind.rawValue).json")
    }

    private static func load(_ kind: RuntimeKind) -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL(kind)) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func save(_ kind: RuntimeKind, _ versions: [RuntimeVersion]) {
        let cache = Cache(fetchedAt: Date(), versions: versions)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL(kind), options: .atomic)
    }
}
