//
//  PHPDiagnosticsSettings.swift
//  CodeEdit
//
//  Settings for the native PHP diagnostics (code-quality rules).
//

import Foundation

extension SettingsData {
    struct PHPDiagnosticsSettings: Codable, Hashable, SearchableSettingsPage {
        var searchKeys: [String] {
            [
                "PHP Diagnostics",
                "Class Length",
                "Method Length",
                "File Length",
                "Parameter Count",
                "Complexity",
                "Strict Types",
                "TODO",
                "Skip Paths",
                "Disabled Rules"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// Max lines for a class/interface/trait/enum body.
        var classLength: Int = 250
        /// Max lines for a function/method body.
        var methodLength: Int = 50
        /// Max lines for the whole file.
        var fileLength: Int = 500
        /// Max parameters for a function/method.
        var parameterCount: Int = 5
        /// Max cyclomatic complexity for a function/method.
        var complexity: Int = 10
        /// Report missing `declare(strict_types=1);`.
        var requireStrictTypes: Bool = true
        /// Report `TODO`/`FIXME` comments as hints.
        var reportTodos: Bool = true
        /// Rule ids that are disabled.
        var disabledRules: [String] = []
        /// Path substrings to skip entirely (e.g. `/vendor/`).
        var skipPatterns: [String] = ["/vendor/", ".generated."]

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.classLength = try container.decodeIfPresent(Int.self, forKey: .classLength) ?? 250
            self.methodLength = try container.decodeIfPresent(Int.self, forKey: .methodLength) ?? 50
            self.fileLength = try container.decodeIfPresent(Int.self, forKey: .fileLength) ?? 500
            self.parameterCount = try container.decodeIfPresent(Int.self, forKey: .parameterCount) ?? 5
            self.complexity = try container.decodeIfPresent(Int.self, forKey: .complexity) ?? 10
            self.requireStrictTypes = try container.decodeIfPresent(Bool.self, forKey: .requireStrictTypes) ?? true
            self.reportTodos = try container.decodeIfPresent(Bool.self, forKey: .reportTodos) ?? true
            self.disabledRules = try container.decodeIfPresent([String].self, forKey: .disabledRules) ?? []
            self.skipPatterns = try container.decodeIfPresent([String].self, forKey: .skipPatterns)
                ?? ["/vendor/", ".generated."]
        }
    }
}
