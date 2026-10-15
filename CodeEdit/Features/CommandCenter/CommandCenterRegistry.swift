//
//  CommandCenterRegistry.swift
//  CodeEdit
//
//  Registers Command Center providers and performs tiered searches across them.
//

import Foundation

/// Holds the registered ``CommandCenterProvider``s and runs searches over them.
///
/// A specific category queries only the providers for that category. The `All` category runs every
/// provider (each capped by its category), then orders the merged results by tier — actions/commands
/// first, content last — preserving each provider's ranking within its tier.
@MainActor
final class CommandCenterRegistry {
    static let shared = CommandCenterRegistry()

    /// The order in which categories appear in the `All` tab (tiers). Content is intentionally last.
    static let tierOrder: [CommandCenterCategory] = [
        .commands, .files, .symbols, .git, .run, .knowledge, .content
    ]

    /// Per-category cap when merging into `All`.
    private static let categoryLimits: [CommandCenterCategory: Int] = [
        .commands: 8,
        .files: 10,
        .symbols: 15,
        .git: 6,
        .run: 6,
        .knowledge: 6,
        .content: 8
    ]

    /// The total cap for a merged `All` search.
    private let totalLimit = 100

    private(set) var providers: [any CommandCenterProvider] = []

    private init() {}

    /// Registers a provider, replacing any existing provider with the same `id`.
    func register(_ provider: any CommandCenterProvider) {
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        providers.sort { $0.priority > $1.priority }
    }

    func providers(for category: CommandCenterCategory) -> [any CommandCenterProvider] {
        providers.filter { $0.category == category }
    }

    /// Searches the providers for a category. `all` merges every provider using tiers.
    func search(_ query: String, category: CommandCenterCategory) async -> [CommandCenterItem] {
        if category != .all {
            var results: [CommandCenterItem] = []
            for provider in providers(for: category) {
                results.append(contentsOf: await provider.search(query))
            }
            return results
        }

        // Query every provider (they are already sorted by descending priority) and bucket by category.
        var buckets: [CommandCenterCategory: [CommandCenterItem]] = [:]
        for provider in providers {
            let items = await provider.search(query)
            guard !items.isEmpty else { continue }
            let limit = Self.categoryLimits[provider.category] ?? 8
            buckets[provider.category, default: []].append(contentsOf: items.prefix(limit))
        }

        // Flatten in tier order, preserving each provider's ranking within its category.
        var ordered: [CommandCenterItem] = []
        for tier in Self.tierOrder {
            if let items = buckets[tier] {
                ordered.append(contentsOf: items)
            }
        }
        return Array(ordered.prefix(totalLimit))
    }
}
