//
//  CommandCenterRegistry.swift
//  CodeEdit
//
//  Registers Command Center providers and performs tiered searches across them.
//

import Foundation

/// Holds the registered ``CommandCenterProvider``s and runs searches over them.
///
/// The `All` category queries every provider (each capped), concatenating results by provider priority;
/// a specific category queries only the providers for that category.
@MainActor
final class CommandCenterRegistry {
    static let shared = CommandCenterRegistry()

    /// The most results any single provider contributes to `All`.
    private let perProviderLimit = 8
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

    /// Searches the providers for a category. `all` merges every provider (each capped).
    func search(_ query: String, category: CommandCenterCategory) async -> [CommandCenterItem] {
        if category != .all {
            var results: [CommandCenterItem] = []
            for provider in providers(for: category) {
                results.append(contentsOf: await provider.search(query))
            }
            return results
        }

        var results: [CommandCenterItem] = []
        for provider in providers {
            let items = await provider.search(query)
            results.append(contentsOf: items.prefix(perProviderLimit))
        }
        return Array(results.prefix(totalLimit))
    }
}
