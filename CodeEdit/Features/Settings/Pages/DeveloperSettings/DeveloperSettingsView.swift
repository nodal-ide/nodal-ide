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

    @AppSettings(\.developerSettings.debugAdapters)
    var debugAdapters

    @AppSettings(\.developerSettings.debugAdapterArguments)
    var debugAdapterArguments

    @AppSettings(\.developerSettings.lspServerArguments)
    var lspServerArguments

    @AppSettings(\.developerSettings.phpDebugClientPort)
    var phpDebugClientPort

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show Internal Development Inspector", isOn: $showInternalDevelopmentInspector)
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

                KeyValueTable(
                    items: $lspServerArguments,
                    keyColumnName: "Server",
                    valueColumnName: "Arguments",
                    newItemInstruction: "Add launch arguments"
                ) {
                    Text("Add launch arguments")
                    Text("Optional launch arguments per language server (space-separated), "
                         + "keyed by package name (e.g. typescript-language-server). Defaults to --stdio.")
                } actionBarTrailing: {
                    EmptyView()
                }
                .frame(minHeight: 96)
            } header: {
                Text("LSP Binaries")
                Text("Specify the language and the absolute path to the language server binary.")
            }

            Section {
                PHPAdapterSettingsRow()

                KeyValueTable(
                    items: $debugAdapters,
                    keyColumnName: "Adapter",
                    valueColumnName: "Debug Adapter Path",
                    newItemInstruction: "Add a debug adapter"
                ) {
                    Text("Add a debug adapter")
                    Text("Specify an adapter id (e.g. php, python, lldb) and the path to its debug adapter executable.")
                } actionBarTrailing: {
                    EmptyView()
                }
                .frame(minHeight: 96)

                KeyValueTable(
                    items: $debugAdapterArguments,
                    keyColumnName: "Adapter",
                    valueColumnName: "Arguments",
                    newItemInstruction: "Add adapter arguments"
                ) {
                    Text("Add adapter arguments")
                    Text("Optional extra command-line arguments passed to the debug adapter (space-separated).")
                } actionBarTrailing: {
                    EmptyView()
                }
                .frame(minHeight: 96)
            } header: {
                Text("Debug Adapters")
                Text("Used by Debug run configurations. The adapter id is referenced from a configuration.")
            }

            Section {
                XdebugStatusRow()
                Stepper("Debug port: \(phpDebugClientPort)", value: $phpDebugClientPort, in: 1...65535, step: 1)
            } header: {
                Text("PHP Debugging")
                Text("Xdebug is enabled per session (XDEBUG_MODE=debug) — your php.ini isn't modified.")
            }

            LocalDomainsSettingsSection()
        }
    }
}
