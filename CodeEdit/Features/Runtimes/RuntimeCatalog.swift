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
        // Homebrew core keeps recent minors; older minors (7.x/5.6) live in the shivammathur/php tap.
        var versions = await fetchPHPCore()
        versions += legacyPHPVersions()
        // Prefer the live (core) entry per minor; keep one row per minor, newest first.
        return deduplicatedByMinor(versions)
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    /// Fetches the stable version for each Homebrew-core PHP formula.
    private static func fetchPHPCore() async -> [RuntimeVersion] {
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
        return versions
    }

    /// Older PHP minors installed via the `shivammathur/php` tap (for legacy projects).
    /// Also a fallback when Homebrew's API is unreachable.
    private static func legacyPHPVersions() -> [RuntimeVersion] {
        let legacy: [(version: String, formula: String)] = [
            ("8.4.0", "shivammathur/php/php@8.4"),
            ("8.3.0", "shivammathur/php/php@8.3"),
            ("8.2.0", "shivammathur/php/php@8.2"),
            ("8.1.0", "shivammathur/php/php@8.1"),
            ("8.0.30", "shivammathur/php/php@8.0"),
            ("7.4.33", "shivammathur/php/php@7.4"),
            ("7.3.33", "shivammathur/php/php@7.3"),
            ("7.2.34", "shivammathur/php/php@7.2"),
            ("7.1.33", "shivammathur/php/php@7.1"),
            ("7.0.33", "shivammathur/php/php@7.0"),
            ("5.6.40", "shivammathur/php/php@5.6")
        ]
        return legacy.map { RuntimeVersion(version: $0.version, installIdentifier: $0.formula) }
    }

    /// Keeps one entry per major.minor (first occurrence wins), preserving order.
    private static func deduplicatedByMinor(_ versions: [RuntimeVersion]) -> [RuntimeVersion] {
        var seen = Set<String>()
        return versions.filter { version in
            let minor = version.version.split(separator: ".").prefix(2).joined(separator: ".")
            return seen.insert(minor).inserted
        }
    }

    // MARK: - Cache

    private struct Cache: Codable {
        /// Bumped when the catalog's shape changes, to invalidate previously cached files.
        let schema: Int?
        let fetchedAt: Date
        let versions: [RuntimeVersion]

        static let currentSchema = 2
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

    /// Removes cached catalogs older than `maxAge` (default 30 days).
    static func pruneStaleCache(olderThan maxAge: TimeInterval = 30 * 24 * 3600) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: keys
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for entry in entries {
            let date = (try? entry.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            if date < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    private static func load(_ kind: RuntimeKind) -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL(kind)),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.schema == Cache.currentSchema else {
            return nil
        }
        return cache
    }

    private static func save(_ kind: RuntimeKind, _ versions: [RuntimeVersion]) {
        let cache = Cache(schema: Cache.currentSchema, fetchedAt: Date(), versions: versions)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL(kind), options: .atomic)
    }
}
