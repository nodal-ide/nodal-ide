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

    @State private var showAdvanced = false

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

            commandSection

            if configuration.kind == .debug {
                programSection
            }

            Section {
                Toggle("Advanced Options", isOn: $showAdvanced)
            }

            if showAdvanced {
                advancedSections
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: configureDefaults)
    }

    // MARK: - Sections

    private var commandSection: some View {
        Section {
            TextField("Command", text: $configuration.command, prompt: Text("php forge.php serve"))
                .accessibilityLabel("Run Command")
            TextField("Working Directory", text: $configuration.workingDirectory, prompt: Text("Workspace root"))
                .accessibilityLabel("Working Directory")
        } header: {
            Text(configuration.kind == .debug ? "Run Command" : "Command")
        } footer: {
            if configuration.kind == .debug {
                Text(
                    "The command that starts your app. Debug runs it with Xdebug enabled and listens "
                    + "for connections — no manual server or listener needed."
                )
                .font(.caption)
            } else {
                Text(
                    "Working directory is relative to the workspace (or absolute). "
                    + "Leave empty for the workspace root."
                )
                    .font(.caption)
            }
        }
    }

    private var programSection: some View {
        Section {
            TextField("Program", text: programBinding, prompt: Text("Script to debug (optional)"))
        } header: {
            Text("Program")
        } footer: {
            Text(
                "Leave empty to run the Command above and listen. Set a script to launch it directly "
                + "(CLI debugging)."
            )
            .font(.caption)
        }
    }

    @ViewBuilder private var advancedSections: some View {
        if configuration.kind == .debug {
            Section {
                Picker("Adapter", selection: adapterBinding) {
                    Text("Automatic").tag("")
                    ForEach(adapterNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("Request", selection: requestBinding) {
                    Text("Launch").tag("launch")
                    Text("Attach").tag("attach")
                }
                TextField("Arguments", text: argumentsBinding, prompt: Text("--flag value"))
                TextField("Client Port", text: clientPortBinding, prompt: Text("9003"))
                pathMappingRows
            } header: {
                Text("Debug Adapter")
            } footer: {
                Text("Automatic uses the first installed adapter. Client port defaults to the Developer setting.")
                    .font(.caption)
            }
        }

        Section {
            ForEach($configuration.environment) { $variable in
                HStack {
                    TextField("Key", text: $variable.key)
                    TextField("Value", text: $variable.value)
                }
            }
            .onDelete { configuration.environment.remove(atOffsets: $0) }
            Button {
                configuration.environment.append(RunConfiguration.EnvironmentVariable())
            } label: {
                Label("Add Variable", systemImage: "plus")
            }
        } header: {
            Text("Environment Variables")
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
            Text("Tasks")
        }
    }

    private var pathMappingRows: some View {
        Group {
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
        }
    }

    // MARK: - Helpers

    /// Expands the advanced section when the configuration already uses advanced settings.
    private func configureDefaults() {
        if configuration.kind == .debug {
            showAdvanced = configuration.adapter != nil
                || configuration.clientPort != nil
                || configuration.arguments != nil
                || !(configuration.pathMappings ?? []).isEmpty
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

    /// `preLaunchTask` is optional; the picker/text field use an empty string for "none".
    private var preLaunchTaskBinding: Binding<String> {
        Binding {
            configuration.preLaunchTask ?? ""
        } set: { newValue in
            configuration.preLaunchTask = newValue.isEmpty ? nil : newValue
        }
    }
}
