//
//  ExtensionsSettings.swift
//  CodeEdit
//

import Foundation

extension SettingsData {
    /// Installed language-extension preferences (edited from the Extensions window, not a settings page).
    struct ExtensionsSettings: Codable, Hashable {
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
