//
//  CommandCenterProvider.swift
//  CodeEdit
//
//  The SPI a Command Center search source implements.
//

import Foundation

/// A source of Command Center results (one per category/tab).
///
/// Providers are registered with ``CommandCenterRegistry``. Higher `priority` providers are consulted
/// first and their results are preferred when merging.
@MainActor
protocol CommandCenterProvider: AnyObject {
    /// A stable identifier for the provider.
    var id: String { get }
    /// The category/tab this provider feeds.
    var category: CommandCenterCategory { get }
    /// Tiers providers within the same category (higher = preferred). Default `0`.
    var priority: Int { get }
    /// Returns results for a query (empty query returns recents/defaults).
    func search(_ query: String) async -> [CommandCenterItem]
}

extension CommandCenterProvider {
    var priority: Int { 0 }
}
