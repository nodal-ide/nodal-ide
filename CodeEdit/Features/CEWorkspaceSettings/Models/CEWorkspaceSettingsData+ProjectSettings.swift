//
//  ProjectCEWorkspaceSettings.swift
//  CodeEdit
//
//  Created by Axel Martinez on 27/3/24.
//

import SwiftUI

class ProjectSettings: ObservableObject, Codable {
    var projectName: String = ""

    /// Declared language of the project, e.g. `"php"`. When set, language extensions for this
    /// language are considered without scanning the workspace for framework markers.
    var language: String = ""

    /// Declared frameworks/libraries the project uses, e.g. `["laravel/framework"]`. Used to
    /// activate framework language extensions without detection.
    var frameworks: [String] = []

    /// Per-project activation overrides keyed by installed extension ID. Missing means inherit
    /// the extension's manifest activation rules; a global disable still wins.
    var extensionOverrides: [String: ExtensionActivationOverride] = [:]

    init() {}

    /// Explicit decoder init for setting default values when key is not present in `JSON`
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        self.frameworks = try container.decodeIfPresent([String].self, forKey: .frameworks) ?? []
        self.extensionOverrides = try container.decodeIfPresent(
            [String: ExtensionActivationOverride].self,
            forKey: .extensionOverrides
        ) ?? [:]
    }

    func isEmpty() -> Bool {
        projectName == "" && language == "" && frameworks.isEmpty && extensionOverrides.isEmpty
    }
}
