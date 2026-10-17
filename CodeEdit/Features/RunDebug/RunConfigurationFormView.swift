//
//  RunConfigurationFormView.swift
//  CodeEdit
//
//  Editor form for a run/debug/test configuration.
//

import SwiftUI

struct RunConfigurationFormView: View {
    @Binding var configuration: RunConfiguration
    /// Names of workspace tasks, offered as pre-launch tasks.
    var taskNames: [String] = []

    private static let matcherNames = ["$gcc", "$tsc"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $configuration.name)

                Picker("Kind", selection: $configuration.kind) {
                    ForEach(RunConfiguration.Kind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
            }

            Section {
                TextField("Command", text: $configuration.command)
                    .accessibilityLabel("Run Command")
                TextField("Working Directory", text: $configuration.workingDirectory)
                    .accessibilityLabel("Working Directory")
            } footer: {
                Text(

                    "Working directory is relative to the workspace (or absolute). "

                    + "Leave empty for the workspace root."

                )
                    .font(.caption)
            }

            Section {
                ForEach($configuration.environment) { $variable in
                    HStack {
                        TextField("Key", text: $variable.key)
                        TextField("Value", text: $variable.value)
                    }
                }
                .onDelete { offsets in
                    configuration.environment.remove(atOffsets: offsets)
                }
                Button {
                    configuration.environment.append(RunConfiguration.EnvironmentVariable())
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
            } header: {
                Text("Environment Variables")
            }

            if configuration.kind == .debug {
                Section {
                    Picker("Adapter", selection: adapterBinding) {
                        Text("None").tag("")
                        ForEach(adapterNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Picker("Request", selection: requestBinding) {
                        Text("Launch").tag("launch")
                        Text("Attach").tag("attach")
                    }
                    TextField("Program", text: programBinding, prompt: Text("Path to the program to debug"))
                    TextField("Arguments", text: argumentsBinding, prompt: Text("--flag value"))
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Configure debug adapters in Settings ▸ Developer ▸ Debug Adapters.")
                        .font(.caption)
                }

                Section {
                    TextField("Port", text: clientPortBinding, prompt: Text("9003"))
                    ForEach(pathMappingsBinding) { $mapping in
                        HStack {
                            TextField("Local Path", text: $mapping.key)
                            TextField("Remote Path", text: $mapping.value)
                        }
                    }
                    .onDelete { configuration.pathMappings?.remove(atOffsets: $0) }
                    Button {
                        var mappings = configuration.pathMappings ?? []
                        mappings.append(RunConfiguration.EnvironmentVariable())
                        configuration.pathMappings = mappings
                    } label: {
                        Label("Add Path Mapping", systemImage: "plus")
                    }
                } header: {
                    Text("PHP / Xdebug")
                } footer: {
                    Text(
                        "Client port Xdebug connects to (default 9003). "
                        + "Path mappings map local → remote (Docker/remote)."
                    )
                        .font(.caption)
                }
            }

            Section {
                Picker("Problem Matcher", selection: $configuration.problemMatcher) {
                    Text("None").tag(String?.none)
                    ForEach(Self.matcherNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }

                if taskNames.isEmpty {
                    TextField("Pre-launch Task", text: preLaunchTaskBinding, prompt: Text("Task name"))
                } else {
                    Picker("Pre-launch Task", selection: preLaunchTaskBinding) {
                        Text("None").tag("")
                        ForEach(taskNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
            } header: {
                Text("Advanced")
            }
        }
        .formStyle(.grouped)
    }

    /// `preLaunchTask` is optional; the picker/text field use an empty string for "none".
    private var preLaunchTaskBinding: Binding<String> {
        Binding {
            configuration.preLaunchTask ?? ""
        } set: { newValue in
            configuration.preLaunchTask = newValue.isEmpty ? nil : newValue
        }
    }

    private var adapterNames: [String] {
        Settings.shared.preferences.developerSettings.debugAdapters.keys.sorted()
    }

    private var adapterBinding: Binding<String> {
        Binding {
            configuration.adapter ?? ""
        } set: { configuration.adapter = $0.isEmpty ? nil : $0 }
    }

    private var requestBinding: Binding<String> {
        Binding {
            configuration.debugRequest ?? "launch"
        } set: { configuration.debugRequest = $0 }
    }

    private var programBinding: Binding<String> {
        Binding {
            configuration.program ?? ""
        } set: { configuration.program = $0.isEmpty ? nil : $0 }
    }

    private var argumentsBinding: Binding<String> {
        Binding {
            configuration.arguments ?? ""
        } set: { configuration.arguments = $0.isEmpty ? nil : $0 }
    }

    private var clientPortBinding: Binding<String> {
        Binding {
            configuration.clientPort.map(String.init) ?? ""
        } set: { newValue in
            configuration.clientPort = Int(newValue.trimmingCharacters(in: .whitespaces))
        }
    }

    private var pathMappingsBinding: Binding<[RunConfiguration.EnvironmentVariable]> {
        Binding {
            configuration.pathMappings ?? []
        } set: { newValue in
            configuration.pathMappings = newValue
        }
    }
}
