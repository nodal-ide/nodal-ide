//
//  InternalLanguage.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors.
//

import Foundation
import LanguageServerProtocol

/// Languages that ship with an in-process, native implementation and therefore do not require an external language
/// server.
///
/// Each can be toggled in **Settings ▸ Developer ▸ Internal Languages**. When enabled, the native engine is used and
/// the LSP path is skipped entirely (no server is started and no LSP highlight provider is installed). When disabled,
/// the app falls back to a language server for that language.
enum InternalLanguage: String, CaseIterable, Identifiable {
    case php

    var id: String { rawValue }

    /// The human-readable name shown in settings.
    var displayName: String {
        switch self {
        case .php:
            return "PHP"
        }
    }

    /// The LSP language identifier this internal language replaces.
    var languageIdentifier: LanguageIdentifier {
        switch self {
        case .php:
            return .php
        }
    }

    /// Whether an internal implementation exists for the given LSP language identifier.
    static func implementing(_ languageId: LanguageIdentifier) -> InternalLanguage? {
        allCases.first(where: { $0.languageIdentifier.rawValue == languageId.rawValue })
    }

    /// The identifiers enabled by default (internal engines preferred over LSP out of the box).
    static let defaultEnabledIdentifiers: [String] = [InternalLanguage.php.rawValue]

    /// Whether the internal implementation for `languageId` is enabled in the given developer settings.
    static func isEnabled(_ languageId: LanguageIdentifier, in settings: SettingsData.DeveloperSettings) -> Bool {
        guard let language = implementing(languageId) else { return false }
        return settings.internalLanguages.contains(language.rawValue)
    }
}
