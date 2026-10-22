//
//  ExtensionPublishView.swift
//  CodeEdit
//

import AppKit
import CodeEditLang
import SwiftUI

struct ExtensionPublishView: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject private var languageManager: LanguageExtensionManager
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @AppSettings(\.extensions.registry)
    private var registry

    @State private var selectedID: String?
    @State private var selectedFolder: URL?
    @State private var pushAfterCommit = true
    @State private var preparation: ExtensionPublishPreparation?
    @State private var result: ExtensionPublishResult?
    @State private var retrySucceeded = false
    @State private var isWorking = false
    @State private var isShowingRegistrySetup = false
    @State private var errorMessage: String?

    init(initialExtension: InstalledLanguageExtension?) {
        _selectedID = State(initialValue: initialExtension?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Package & Publish Extension")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .disabled(isWorking)
            }
            .padding(20)
            Divider()

            if let result {
                ExtensionPublishResultView(
                    result: result,
                    retrySucceeded: $retrySucceeded,
                    isWorking: $isWorking,
                    errorMessage: $errorMessage,
                    onRetry: { retryPush() },
                    onDone: { dismiss() }
                )
            } else if let preparation {
                ExtensionPublishReviewView(
                    preparation: preparation,
                    pushAfterCommit: $pushAfterCommit,
                    isWorking: $isWorking,
                    errorMessage: $errorMessage,
                    onBack: {
                        preparation.artifact.removeTemporaryFiles()
                        self.preparation = nil
                        errorMessage = nil
                    },
                    onPublish: { publish(preparation) }
                )
            } else {
                setupContent
            }
        }
        .frame(width: 760, height: 620)
        .onAppear {
            if selectedID == nil, selectedFolder == nil, installed.count == 1 {
                selectedID = installed.first?.id
            }
        }
        .onDisappear {
            preparation?.artifact.removeTemporaryFiles()
        }
        .sheet(isPresented: $isShowingRegistrySetup) {
            ExtensionRegistrySetupView(configuration: nil)
                .environmentObject(marketplace)
        }
    }

    private var installed: [InstalledLanguageExtension] {
        languageManager.extensions.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedExtension: InstalledLanguageExtension? {
        guard let selectedID else { return nil }
        return installed.first { $0.id == selectedID }
    }

    private var packageRoot: URL? {
        selectedFolder ?? selectedExtension?.root
    }

    private var setupContent: some View {
        VStack(spacing: 0) {
            Form {
                Section("Extension") {
                    Picker("Installed Extension", selection: $selectedID) {
                        Text("Choose an extension").tag(String?.none)
                        ForEach(installed) { ext in
                            Text(extensionLabel(ext)).tag(Optional(ext.id))
                        }
                    }
                    .onChange(of: selectedID) {
                        selectedFolder = nil
                        errorMessage = nil
                    }

                    HStack {
                        if let selectedFolder {
                            Label(selectedFolder.path(percentEncoded: false), systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Or publish a package folder that is not installed.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Folder…") { choosePackageFolder() }
                        if selectedFolder != nil {
                            Button("Use Installed") {
                                selectedFolder = nil
                            }
                        }
                    }
                }

                Section("Registry") {
                    if let registry {
                        LabeledContent("Name", value: registry.name)
                        LabeledContent("Folder", value: registry.workingCopyPath)
                        LabeledContent("Branch", value: registry.branch)
                        if let catalogURL = registry.catalogURL {
                            LabeledContent("Catalog", value: catalogURL)
                        }
                    } else {
                        Text("No publishing registry is configured.")
                            .foregroundStyle(.secondary)
                        Button("Create Registry…") { isShowingRegistrySetup = true }
                    }
                }

                Section("Git") {
                    Toggle("Push after committing", isOn: $pushAfterCommit)
                        .disabled(registry == nil)
                        .onChange(of: registry) {
                            if registry == nil {
                                pushAfterCommit = false
                            }
                        }
                    Text(
                        "Publishing always validates the package and creates a local commit. "
                            + "Pushing uses your existing SSH credentials and never prompts for a password."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                errorContent
            }
            .formStyle(.grouped)

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Review Publish…") { prepare() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || registry == nil || packageRoot == nil)
            }
            .padding(20)
        }
    }

    @ViewBuilder private var errorContent: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func extensionLabel(_ ext: InstalledLanguageExtension) -> String {
        if let version = ext.version {
            return "\(ext.name) · \(version)"
        }
        return ext.name
    }

    private func choosePackageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFolder = url
        selectedID = nil
        errorMessage = nil
    }

    private func prepare() {
        guard let registry else {
            errorMessage = "Create or select a registry first."
            return
        }
        guard let packageRoot else {
            errorMessage = "Choose an installed extension or a package folder."
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let prepared = try await AppServices.extensionRegistryService.preparePublish(
                    configuration: registry,
                    packageAt: packageRoot
                )
                preparation = prepared
                if prepared.remote == nil {
                    pushAfterCommit = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func publish(_ preparation: ExtensionPublishPreparation) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                result = try await AppServices.extensionRegistryService.publish(
                    preparation: preparation,
                    pushAfterCommit: pushAfterCommit
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func retryPush() {
        guard let registry else {
            errorMessage = "The registry configuration is missing."
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                _ = try await AppServices.extensionRegistryService.retryPendingPush(
                    configuration: registry
                )
                retrySucceeded = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
