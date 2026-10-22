//
//  ExtensionRegistrySetupView.swift
//  CodeEdit
//

import AppKit
import SwiftUI

struct ExtensionRegistrySetupView: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @AppSettings(\.extensions.registry)
    private var registry

    private let configuration: ExtensionRegistryConfiguration?

    @State private var name: String
    @State private var location: String
    @State private var branch: String
    @State private var cloneURL: String
    @State private var catalogURL: String
    @State private var cloneFromGit: Bool
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(configuration: ExtensionRegistryConfiguration?) {
        self.configuration = configuration
        _name = State(initialValue: configuration?.name ?? "")
        _location = State(initialValue: configuration?.workingCopyPath ?? "")
        _branch = State(initialValue: configuration?.branch ?? "main")
        _cloneURL = State(initialValue: "")
        _catalogURL = State(initialValue: configuration?.catalogURL ?? "")
        _cloneFromGit = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(configuration == nil ? "Create Extension Registry" : "Edit Extension Registry")
                .font(.title2.weight(.semibold))

            Form {
                if configuration == nil {
                    Picker("Setup", selection: $cloneFromGit) {
                        Text("Local Folder").tag(false)
                        Text("Clone from Git").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                TextField("Name", text: $name, prompt: Text("Team Registry"))
                HStack {
                    TextField(
                        "Folder",
                        text: $location,
                        prompt: Text("/Users/me/Development/team-registry")
                    )
                    Button("Choose…") { chooseFolder() }
                }
                if cloneFromGit {
                    TextField(
                        "Clone URL",
                        text: $cloneURL,
                        prompt: Text("git@github.com:team/registry.git")
                    )
                }
                TextField("Branch", text: $branch, prompt: Text("main"))
                TextField(
                    "Catalog URL",
                    text: $catalogURL,
                    prompt: Text("https://example.com/extensions.json")
                )
            }
            .formStyle(.grouped)

            Text(
                "The registry is a Git checkout containing extensions.json and "
                    + "extensions/<id>/<version>/<version>.zip. Publishing commits only the new "
                    + "ZIP and catalog entry. A hosted catalog URL can be added as an untrusted "
                    + "source so you can review it before trusting it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button(configuration == nil ? "Create Registry" : "Save Registry") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !location.isEmpty {
            panel.directoryURL = URL(filePath: location, directoryHint: .isDirectory)
                .deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        location = url.path(percentEncoded: false)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.lastPathComponent
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCloneURL = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCatalogURL = catalogURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a registry name."
            return
        }
        guard !trimmedLocation.isEmpty else {
            errorMessage = "Choose a folder for the registry."
            return
        }
        guard !trimmedBranch.isEmpty else {
            errorMessage = "Enter the Git branch to publish to."
            return
        }
        if cloneFromGit, trimmedCloneURL.isEmpty {
            errorMessage = "Enter the Git clone URL."
            return
        }
        if !trimmedCatalogURL.isEmpty {
            guard let url = URL(string: trimmedCatalogURL),
                  url.scheme?.lowercased() == "https",
                  url.host != nil,
                  url.user == nil,
                  url.password == nil else {
                errorMessage = "The catalog URL must be HTTPS and cannot contain credentials."
                return
            }
        }

        isWorking = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await AppServices.extensionRegistryService.initialize(
                    workingCopy: URL(filePath: trimmedLocation, directoryHint: .isDirectory),
                    name: trimmedName,
                    cloneURL: cloneFromGit ? trimmedCloneURL : nil,
                    branch: trimmedBranch,
                    catalogURL: trimmedCatalogURL.isEmpty ? nil : trimmedCatalogURL
                )
                registry = snapshot.configuration
                addSourceIfNeeded(snapshot.configuration)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func addSourceIfNeeded(_ configuration: ExtensionRegistryConfiguration) {
        guard let url = configuration.catalogWebURL else { return }
        guard !marketplace.sources.contains(where: { $0.location == url }) else { return }
        try? marketplace.addSource(
            name: configuration.name,
            location: url,
            trustImmediately: false
        )
    }
}
