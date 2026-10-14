//
//  DeveloperSettingsView.swift
//  CodeEdit
//
//  Created by Abe Malla on 5/16/24.
//

import SwiftUI
import LanguageServerProtocol

/// A view that implements the Developer settings section
struct DeveloperSettingsView: View {
    @AppSettings(\.developerSettings.lspBinaries)
    var lspBinaries

    @AppSettings(\.developerSettings.showInternalDevelopmentInspector)
    var showInternalDevelopmentInspector

    @AppSettings(\.developerSettings.internalLanguages)
    var internalLanguages

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show Internal Development Inspector", isOn: $showInternalDevelopmentInspector)
            }

            Section {
                ForEach(InternalLanguage.allCases) { language in
                    Toggle(language.displayName, isOn: binding(for: language))
                }
            } header: {
                Text("Internal Languages")
                Text(
                    "Use the app's built-in engine for these languages instead of a language server. " +
                    "Disable a language here to use an external language server for it."
                )
            }

            Section {
                KeyValueTable(
                    items: $lspBinaries,
                    validKeys: LanguageIdentifier.allCases.map { $0.rawValue },
                    keyColumnName: "Language",
                    valueColumnName: "Language Server Path",
                    newItemInstruction: "Add a language server"
                ) {
                    Text("Add a language server")
                    Text(
                        "Specify the absolute path to your LSP binary and its associated language."
                    )
                } actionBarTrailing: {
                    EmptyView()
                }
                .frame(minHeight: 96)
            } header: {
                Text("LSP Binaries")
                Text("Specify the language and the absolute path to the language server binary.")
            }
        }
    }

    /// Binding for whether an internal language is enabled. Writes the whole array so the setting persists.
    private func binding(for language: InternalLanguage) -> Binding<Bool> {
        Binding {
            internalLanguages.contains(language.rawValue)
        } set: { isEnabled in
            var languages = internalLanguages
            languages.removeAll { $0 == language.rawValue }
            if isEnabled {
                languages.append(language.rawValue)
            }
            internalLanguages = languages
        }
    }
}
