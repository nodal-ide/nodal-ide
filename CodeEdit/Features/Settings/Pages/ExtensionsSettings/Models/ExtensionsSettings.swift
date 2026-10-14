//
//  ExtensionsSettings.swift
//  CodeEdit
//

import Foundation

extension SettingsData {
    /// Settings for installed language extensions (declarative packs).
    struct ExtensionsSettings: Codable, Hashable, SearchableSettingsPage {
        /// The search keys
        var searchKeys: [String] {
            [
                "Extensions",
                "Language Extensions",
                "Language Packs",
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// Ids of installed extensions the user has disabled. Extensions are enabled by default.
        var disabledExtensions: [String] = []

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.disabledExtensions = try container.decodeIfPresent(
                [String].self,
                forKey: .disabledExtensions
            ) ?? []
        }
    }
}
