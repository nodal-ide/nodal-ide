//
//  ExtensionsSettingsView.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/2/25.
//

import SwiftUI

/// Displays a searchable list of packages from the ``RegistryManager``.
struct LanguageServersView: View {
    @StateObject var registryManager: RegistryManager = .shared
    @StateObject private var searchModel = FuzzySearchUIModel<RegistryItem>()
    @State private var searchText: String = ""
    @State private var selectedInstall: PackageManagerInstallOperation?

    @State private var showingInfoPanel = false

    @AppSettings(\.developerSettings.internalLanguages)
    var internalLanguages

    var body: some View {
        Group {
            SettingsForm {
                if registryManager.isDownloadingRegistry {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }

                Section {
                    ForEach(InternalLanguage.allCases) { language in
                        Toggle(language.displayName, isOn: binding(for: language))
                    }
                } header: {
                    Text("Internal Languages")
                    Text(
                        "These languages are handled by the app's built-in engine, so no language server is "
                        + "downloaded or started for them — they work out of the box. Turn a language off here "
                        + "to use an external language server from the list below instead."
                    )
                }

                Section {
                    List(searchModel.items ?? registryManager.registryItems, id: \.name) { item in
                        LanguageServerRowView(
                            package: item,
                            onCancel: {
                                registryManager.cancelInstallation()
                            },
                            onInstall: { [item] in
                                do {
                                    selectedInstall = try registryManager.installOperation(package: item)
                                } catch {
                                    // Display the error
                                    NSAlert(error: error).runModal()
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                    .searchable(text: $searchText)
                    .onChange(of: searchText) { _, newValue in
                        searchModel.searchTextUpdated(searchText: newValue, allItems: registryManager.registryItems)
                    }
                } header: {
                    Label(
                        "Warning: Language server installation is experimental. Use at your own risk.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }
            }
            .sheet(item: $selectedInstall) { operation in
                LanguageServerInstallView(operation: operation)
            }
        }
        .environmentObject(registryManager)
    }

    private func getInfoString() -> AttributedString {
        let string = "CodeEdit makes use of the Mason Registry for language server installation. To install a package, "
        + "CodeEdit uses the package manager directed by the Mason Registry, and installs a copy of "
        + "the language server in Application Support.\n\n"
        + "Language server installation is still experimental, there may be bugs and expect this flow "
        + "to change over time."

        var attrString = AttributedString(string)

        if let linkRange = attrString.range(of: "Mason Registry") {
            attrString[linkRange].link = URL(string: "https://mason-registry.dev/")
            attrString[linkRange].foregroundColor = NSColor.linkColor
        }

        return attrString
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
